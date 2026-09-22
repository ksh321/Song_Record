"""P04-09: real concurrent TJ-number registration on a disposable MySQL V7 DB.

Run through verify_p04_disposable.py --scope tj-race, not against a development DB.
Uses two open mysql clients. MySQL's data_lock_waits must show the second writer
blocked by the first on uq_song_owner_reserved_tj before the first may commit.
No time-based sleep stands in for evidence that the transactions overlap.
Root is used only to inspect lock waits inside the generated test container.
Lock ownership is resolved by engine transaction IDs, not lock-creation thread IDs.

https://dev.mysql.com/doc/refman/8.4/en/performance-schema-data-lock-waits-table.html
https://dev.mysql.com/doc/refman/8.4/en/information-schema-innodb-trx-table.html
"""

import os
import queue
import re
import subprocess
import threading
import time

from verify_p04_extended_schema import query, uid


def client_command(*, root=False):
    credential = ('MYSQL_PWD="$MYSQL_ROOT_PASSWORD"' if root else
                  'MYSQL_PWD="$MYSQL_PASSWORD"')
    user = '-uroot' if root else '-u"$MYSQL_USER"'
    return ['docker', 'compose', 'exec', '-T', 'mysql', 'sh', '-lc',
            f'{credential} mysql --no-defaults --protocol=tcp -h127.0.0.1 {user} '
            '"$MYSQL_DATABASE" --default-character-set=utf8mb4 --batch '
            '--skip-column-names --unbuffered --raw']


def observe(statement):
    result = subprocess.run(client_command(root=True), input=statement + '\n',
                            text=True, encoding='utf-8', capture_output=True, timeout=10)
    if result.returncode:
        raise RuntimeError('Lock observation failed: ' + result.stderr)
    return result.stdout.strip()


class Session:
    """One connection that remains open across an explicit transaction barrier."""

    def __init__(self):
        self.process = subprocess.Popen(client_command(), stdin=subprocess.PIPE,
                                        stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
                                        text=True, encoding='utf-8', bufsize=1)
        self.lines = queue.Queue()
        self.history = []

        def receive():
            try:
                for line in self.process.stdout:
                    self.lines.put(line.rstrip('\r\n'))
            finally:
                self.lines.put(None)

        self.reader = threading.Thread(target=receive, daemon=True)
        self.reader.start()
        try:
            self.send("SET time_zone='+00:00'; SET SESSION innodb_lock_wait_timeout=30; "
                      "SELECT CONCAT('P04_CONNECTION=',CONNECTION_ID());")
            connection = self.until(lambda line: line.startswith('P04_CONNECTION='))
            self.connection_id = int(connection.split('=', 1)[1])
        except BaseException:
            self.close()
            raise

    def send(self, statement):
        self.process.stdin.write(statement + '\n')
        self.process.stdin.flush()

    def until(self, predicate, *, timeout=20):
        deadline = time.monotonic() + timeout
        while True:
            remaining = deadline - time.monotonic()
            if remaining <= 0:
                raise RuntimeError('SQL client response timed out: ' + '\n'.join(self.history))
            try:
                line = self.lines.get(timeout=remaining)
            except queue.Empty as error:
                raise RuntimeError('SQL client response timed out') from error
            if line is None:
                raise RuntimeError('SQL client ended early: ' + '\n'.join(self.history))
            self.history.append(line)
            if line.startswith('ERROR '):
                raise RuntimeError('Unexpected SQL failure: ' + line)
            if predicate(line):
                return line

    def command(self, statement, marker):
        self.send(statement + f"; SELECT '{marker}';")
        self.until(lambda line: line == marker)

    def expect_duplicate(self):
        deadline = time.monotonic() + 20
        while True:
            remaining = deadline - time.monotonic()
            if remaining <= 0:
                raise RuntimeError('Expected duplicate error but client did not finish')
            try:
                line = self.lines.get(timeout=remaining)
            except queue.Empty as error:
                raise RuntimeError('Expected duplicate error but client did not finish') from error
            if line is None:
                break
            self.history.append(line)
        output = '\n'.join(self.history)
        code = self.process.wait(timeout=5)
        if code == 0 or 'ERROR 1062 ' not in output or 'uq_song_owner_reserved_tj' not in output:
            raise RuntimeError('Expected the account TJ unique-key error: ' + output)

    def collect_available(self):
        """Keep early errors/completion visible instead of reporting only a timeout."""
        received = []
        while True:
            try:
                line = self.lines.get_nowait()
            except queue.Empty:
                return received
            if line is None:
                received.append('<client EOF>')
            else:
                received.append(line)
                self.history.append(line)

    def close(self):
        # EOF closes this batch client and rolls back its own uncommitted work.
        try:
            self.process.stdin.close()
        except (BrokenPipeError, OSError):
            pass
        try:
            self.process.wait(timeout=5)
        except subprocess.TimeoutExpired:
            self.process.terminate()
            try:
                self.process.wait(timeout=5)
            except subprocess.TimeoutExpired:
                self.process.kill()
                self.process.wait(timeout=5)
        self.reader.join(timeout=2)
        self.process.stdout.close()

    def __enter__(self):
        return self

    def __exit__(self, *_):
        self.close()


def unique_wait_sql(first_connection_id, second_connection_id):
    # InnoDB can materialize A's implicit INSERT lock while B requests it. The
    # lock structure then carries B's creation-event thread ID despite belonging
    # to A's transaction. Resolve both owners through INNODB_TRX instead.
    # MySQL 8.4: storage/innobase/lock/lock0lock.cc, lock_alloc /
    # lock_rec_convert_impl_to_expl_for_trx; handler/p_s.cc exposes that event ID.
    return f"""
SELECT COUNT(*)
FROM performance_schema.data_lock_waits w
JOIN information_schema.INNODB_TRX requesting
  ON requesting.TRX_ID=w.REQUESTING_ENGINE_TRANSACTION_ID
JOIN information_schema.INNODB_TRX blocking
  ON blocking.TRX_ID=w.BLOCKING_ENGINE_TRANSACTION_ID
JOIN performance_schema.data_locks requested
  ON requested.ENGINE=w.ENGINE AND requested.ENGINE_LOCK_ID=w.REQUESTING_ENGINE_LOCK_ID
JOIN performance_schema.data_locks held
  ON held.ENGINE=w.ENGINE AND held.ENGINE_LOCK_ID=w.BLOCKING_ENGINE_LOCK_ID
WHERE w.ENGINE='INNODB'
  AND requesting.TRX_MYSQL_THREAD_ID={int(second_connection_id)}
  AND blocking.TRX_MYSQL_THREAD_ID={int(first_connection_id)}
  AND requesting.TRX_STATE='LOCK WAIT'
  AND requested.ENGINE_TRANSACTION_ID=requesting.TRX_ID
  AND held.ENGINE_TRANSACTION_ID=blocking.TRX_ID
  AND requested.LOCK_STATUS='WAITING' AND held.LOCK_STATUS='GRANTED'
  AND requested.OBJECT_SCHEMA=DATABASE() AND requested.OBJECT_NAME='song'
  AND requested.INDEX_NAME='uq_song_owner_reserved_tj'
  AND held.OBJECT_SCHEMA=DATABASE() AND held.OBJECT_NAME='song'
  AND held.INDEX_NAME='uq_song_owner_reserved_tj';
"""


def diagnose_wait(first, second):
    """Read only this disposable run's connections and synthetic song locks."""
    ids = f'{int(first.connection_id)},{int(second.connection_id)}'
    print(f'DIAG: expected waiting connection={second.connection_id}, '
          f'blocking connection={first.connection_id}', flush=True)
    for name, session in (('first', first), ('second', second)):
        session.collect_available()
        print(f'DIAG: {name} client exit={session.process.poll()} '
              f'output={session.history!r}', flush=True)
    try:
        print(observe(f"""
SELECT 'DIAG_SERVER', @@version, @@performance_schema, DATABASE();
SELECT 'DIAG_TRX', TRX_ID, TRX_MYSQL_THREAD_ID, TRX_STATE,
       TRX_REQUESTED_LOCK_ID, LEFT(TRX_QUERY,300)
FROM information_schema.INNODB_TRX WHERE TRX_MYSQL_THREAD_ID IN ({ids});
SELECT 'DIAG_WAIT', w.REQUESTING_ENGINE_TRANSACTION_ID,
       w.BLOCKING_ENGINE_TRANSACTION_ID, w.REQUESTING_THREAD_ID, w.BLOCKING_THREAD_ID,
       r.TRX_MYSQL_THREAD_ID, b.TRX_MYSQL_THREAD_ID,
       w.REQUESTING_ENGINE_LOCK_ID, w.BLOCKING_ENGINE_LOCK_ID
FROM performance_schema.data_lock_waits w
LEFT JOIN information_schema.INNODB_TRX r ON r.TRX_ID=w.REQUESTING_ENGINE_TRANSACTION_ID
LEFT JOIN information_schema.INNODB_TRX b ON b.TRX_ID=w.BLOCKING_ENGINE_TRANSACTION_ID
WHERE r.TRX_MYSQL_THREAD_ID IN ({ids}) OR b.TRX_MYSQL_THREAD_ID IN ({ids});
SELECT 'DIAG_LOCK', ENGINE_LOCK_ID, ENGINE_TRANSACTION_ID, THREAD_ID,
       INDEX_NAME, LOCK_TYPE, LOCK_MODE, LOCK_STATUS
FROM performance_schema.data_locks
WHERE OBJECT_SCHEMA=DATABASE() AND OBJECT_NAME='song';
SELECT 'DIAG_CONNECTION', PROCESSLIST_ID, PROCESSLIST_COMMAND, PROCESSLIST_STATE,
       LEFT(PROCESSLIST_INFO,300)
FROM performance_schema.threads WHERE PROCESSLIST_ID IN ({ids});
"""), flush=True)
    except Exception as diagnostic_error:
        print('DIAG: could not read lock details: ' + str(diagnostic_error), flush=True)


def wait_for_unique_key(first, second):
    deadline = time.monotonic() + 20
    sql = unique_wait_sql(first.connection_id, second.connection_id)
    try:
        while time.monotonic() < deadline:
            early_output = second.collect_available()
            if early_output:
                raise RuntimeError('Competing client responded before a lock wait was observed: '
                                   + '\n'.join(early_output))
            if first.process.poll() is not None or second.process.poll() is not None:
                raise RuntimeError('A competing connection ended before the lock wait was observed')
            if int(observe(sql)) > 0:
                print('PASS: observed overlapping transactions on account TJ unique key '
                      f'(waiting connection={second.connection_id}, '
                      f'blocking connection={first.connection_id})', flush=True)
                return
            time.sleep(0.05)
        raise RuntimeError('No actual TJ unique-index lock wait was observed')
    except Exception:
        diagnose_wait(first, second)
        raise


def require(condition, label):
    if not condition:
        raise RuntimeError(label)
    print('PASS: ' + label, flush=True)


def insert(identifier, owner, number):
    return ("INSERT INTO song(id,user_id,source_type,tj_number,title,artist,note) VALUES "
            f"({uid(identifier)},{uid(owner)},'TJ','{number}','P04-09 fixture','synthetic','')")


def main():
    print('P04-09 TJ verifier v2: transaction-owner lock observation', flush=True)
    project = os.environ.get('COMPOSE_PROJECT_NAME', '')
    if (os.environ.get('P04_DISPOSABLE_DB') != '1' or
            os.environ.get('MYSQL_DATABASE') != 'song_record_p0409' or
            not re.fullmatch(r'song-record-p0409-[0-9a-f]{16}', project) or
            not os.environ.get('COMPOSE_FILE') or os.environ.get('MYSQL_TEST_CLIENT')):
        raise RuntimeError('Use verify_p04_disposable.py --scope tj-race to create an isolated test DB')
    require(query('SELECT DATABASE()') == 'song_record_p0409', 'isolated test schema selected')
    require(observe('SELECT @@performance_schema;') == '1', 'lock observation is available')
    require(query("SELECT GROUP_CONCAT(version ORDER BY installed_rank) "
                  "FROM flyway_schema_history WHERE success=1") == '1,2,3,4,5,6,7',
            'fresh V1-V7 installation completed')
    owner, other = 190001, 190002
    query(f'INSERT INTO app_user(id) VALUES ({uid(owner)}),({uid(other)})')

    # Case 1: a committed first writer defeats the concurrent duplicate.
    with Session() as first, Session() as second:
        require(first.connection_id != second.connection_id, 'two separate MySQL connections')
        first.command('START TRANSACTION; ' + insert(190010, owner, '000190001'), 'FIRST_HELD')
        second.send('START TRANSACTION; ' + insert(190011, owner, '000190001') +
                    "; COMMIT; SELECT 'SECOND_DONE';")
        wait_for_unique_key(first, second)
        first.command('COMMIT', 'FIRST_COMMITTED')
        second.expect_duplicate()
        require(True, 'same-account concurrent registration returns MySQL 1062')
    require(query(f"SELECT COUNT(*) FROM song WHERE user_id={uid(owner)} "
                  "AND tj_number='000190001'") == '1', 'duplicate race leaves exactly one song')
    require(query(f'SELECT COUNT(*) FROM song WHERE id={uid(190011)}') == '0',
            'rejected writer leaves no partial song')

    # Case 2: an aborted first writer releases the number to the waiting writer.
    with Session() as first, Session() as second:
        first.command('START TRANSACTION; ' + insert(190020, owner, '000190002'), 'FIRST_HELD')
        second.send('START TRANSACTION; ' + insert(190021, owner, '000190002') +
                    "; COMMIT; SELECT 'SECOND_COMMITTED';")
        wait_for_unique_key(first, second)
        first.command('ROLLBACK', 'FIRST_ROLLED_BACK')
        second.until(lambda line: line == 'SECOND_COMMITTED')
        require(True, 'waiting registration succeeds after the first writer rolls back')
    require(query(f"SELECT COUNT(*),MIN(HEX(id)) FROM song WHERE user_id={uid(owner)} "
                  "AND tj_number='000190002'") == f'1\t{190021:032X}',
            'rollback race preserves only the committed second song')

    # Case 3: another account may commit the same number while A remains open.
    with Session() as first, Session() as second:
        first.command('START TRANSACTION; ' + insert(190030, owner, '000190003'), 'FIRST_HELD')
        second.command('START TRANSACTION; ' + insert(190031, other, '000190003') + '; COMMIT',
                       'OTHER_ACCOUNT_COMMITTED')
        require(query(f'SELECT COUNT(*) FROM song WHERE id={uid(190030)}') == '0' and
                query(f'SELECT COUNT(*) FROM song WHERE id={uid(190031)}') == '1',
                'other account committed the same number before the first account committed')
        first.command('COMMIT', 'FIRST_COMMITTED')
    require(query("SELECT COUNT(*),COUNT(DISTINCT user_id) FROM song WHERE tj_number='000190003'")
            == '2\t2', 'same number remains separate across two accounts')
    require(query("SELECT COUNT(*) FROM song WHERE tj_number LIKE '00019000%' "
                  "AND reserved_tj_number=tj_number") == '4', 'leading-zero TJ numbers preserved')
    print('P04-09 TJ number race verification passed.', flush=True)


if __name__ == '__main__':
    main()
