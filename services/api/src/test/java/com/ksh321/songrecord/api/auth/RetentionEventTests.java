package com.ksh321.songrecord.api.auth;

import com.ksh321.songrecord.api.retention.*;
import com.ksh321.songrecord.api.jobs.JobQueue;
import com.ksh321.songrecord.api.revision.RevisionChanges;
import com.ksh321.songrecord.api.sync.AccountChanges;
import java.time.Duration;
import java.util.*;
import org.junit.jupiter.api.*;
import org.springframework.transaction.support.TransactionTemplate;
import static com.ksh321.songrecord.api.songs.SongQueryKeys.bytes;
import static org.assertj.core.api.Assertions.*;

class RetentionEventTests {
    final RecordingLinkingTests setup=new RecordingLinkingTests();
    IdempotencyTests f;UUID song,recording;JobQueue jobs;RetentionSelectionStore store;
    @BeforeEach void open()throws Exception {
        setup.open();f=setup.setup.f;song=setup.song(f.registration.userId(),"ACTIVE");
        var draft=setup.setup.setup;var body=draft.base();body.put("song_id",song.toString());
        assertThat(draft.create(body).getStatus()).isEqualTo(201);recording=draft.id;
        jobs=new JobQueue(f.jdbc,f.access,f.manager,f.clock,Duration.ofSeconds(10),3);
        store=new RetentionSelectionStore(f.jdbc,f.manager);
    }
    @AfterEach void close()throws Exception{setup.close();}
    long count(){return f.jdbc.queryForObject("SELECT COUNT(*) FROM job",Long.class);}
    void saved()throws Exception {
        var file=Map.of("size_bytes",100,"duration_ms",1000,"sha256","a".repeat(64),"codec","AAC_LC","sample_rate",48000,"channels",1,"capture_integrity","VALIDATED");
        assertThat(setup.setup.edit(Map.of("base_revision",1,"metadata_state","SAVED","title_snapshot","title","artist_snapshot","artist","key_mode","ORIGINAL","key_shift",0,"file",file)).getStatus()).isEqualTo(200);
    }
    void mutate(RevisionChanges.Resource resource,UUID id,String sql) {
        var revisions=new RevisionChanges(f.jdbc,f.access,f.manager,f.clock);
        var changes=new AccountChanges(f.jdbc,f.access,f.manager,f.clock);
        new TransactionTemplate(f.manager).execute(s->changes.write(f.account,()->{
            long revision=f.jdbc.queryForObject("SELECT revision FROM "+(resource==RevisionChanges.Resource.SONG?"song":"recording")+" WHERE id=?",Long.class,bytes(id));
            var changed=revisions.change(f.account,resource,id.toString(),revision,before->f.jdbc.update(sql,bytes(id)));
            return new AccountChanges.Batch<>(1,List.of(new AccountChanges.Change(AccountChanges.Entity.valueOf(resource.name()),id,((Number)changed.get("revision")).longValue(),AccountChanges.Operation.UPSERT,"{}")));
        }));
    }
    @Test void saveQueuesAndWorkerSelectsWithoutCloudFile()throws Exception {
        saved();assertThat(count()).isEqualTo(1);
        assertThat(new RetentionWorker(jobs,store).runOnce()).isTrue();
        assertThat(store.recalculate(f.registration.userId(),song).orElseThrow().recordingIds()).containsExactly(recording);
        assertThat(new RetentionWorker(jobs,store).runOnce()).isFalse();
    }
    @Test void deletionRestorationAndSongLifecycleRecalculateWithoutDeletingFiles()throws Exception {
        saved();var worker=new RetentionWorker(jobs,store);worker.runOnce();
        mutate(RevisionChanges.Resource.RECORDING,recording,"UPDATE recording SET lifecycle_state='TRASHED' WHERE id=?");
        worker.runOnce();assertThat(store.recalculate(f.registration.userId(),song).orElseThrow().recordingIds()).isEmpty();
        mutate(RevisionChanges.Resource.RECORDING,recording,"UPDATE recording SET lifecycle_state='ACTIVE' WHERE id=?");
        worker.runOnce();assertThat(store.recalculate(f.registration.userId(),song).orElseThrow().recordingIds()).containsExactly(recording);
        mutate(RevisionChanges.Resource.SONG,song,"UPDATE song SET lifecycle_state='TRASHED' WHERE id=?");
        worker.runOnce();assertThat(store.recalculate(f.registration.userId(),song).orElseThrow().recordingIds()).isEmpty();
        mutate(RevisionChanges.Resource.SONG,song,"UPDATE song SET lifecycle_state='ACTIVE' WHERE id=?");
        worker.runOnce();assertThat(store.recalculate(f.registration.userId(),song).orElseThrow().recordingIds()).containsExactly(recording);
        assertThat(count()).isEqualTo(5);assertThat(f.jdbc.queryForObject("SELECT COUNT(*) FROM recording_file_spec",Long.class)).isEqualTo(1);
    }
    @Test void rollbackIncludesMetadataJobAndSequence()throws Exception {
        saved();long before=count();
        f.jdbc.execute("ALTER TABLE change_log ADD CONSTRAINT reject_event CHECK(revision<3)");
        assertThatThrownBy(()->mutate(RevisionChanges.Resource.RECORDING,recording,"UPDATE recording SET tier='D' WHERE id=?")).isInstanceOf(RuntimeException.class);
        assertThat(count()).isEqualTo(before);assertThat(f.jdbc.queryForObject("SELECT tier FROM recording",String.class)).isNull();
    }
    @Test void lateOlderLeaseReadsCurrentMetadataAndCannotRestorePastSelection()throws Exception {
        saved();var old=jobs.claim(JobQueue.Type.POLICY_RECALCULATE).orElseThrow();
        mutate(RevisionChanges.Resource.RECORDING,recording,"UPDATE recording SET lifecycle_state='TRASHED' WHERE id=?");
        new RetentionWorker(jobs,store).runOnce();var current=store.recalculate(f.registration.userId(),song).orElseThrow();
        assertThat(current.recordingIds()).isEmpty();
        assertThat(jobs.complete(old,()->store.recalculateInJob(f.registration.userId(),song))).isTrue();
        assertThat(store.recalculate(f.registration.userId(),song)).contains(current);
    }
    @Test void leaseExpirationRollsBackSelectionAndRetryRecomputes()throws Exception {
        saved();var lease=jobs.claim(JobQueue.Type.POLICY_RECALCULATE).orElseThrow();
        assertThatThrownBy(()->jobs.complete(lease,()->{store.recalculateInJob(f.registration.userId(),song);f.clock.instant=f.clock.instant.plusSeconds(10);})).isInstanceOf(IllegalStateException.class);
        assertThat(f.jdbc.queryForObject("SELECT COUNT(*) FROM song_cloud_selection",Long.class)).isZero();
        assertThat(new RetentionWorker(jobs,store).runOnce()).isTrue();
        assertThat(store.recalculate(f.registration.userId(),song).orElseThrow().recordingIds()).containsExactly(recording);
    }
    @Test void unrelatedMetadataDoesNotSchedule()throws Exception {
        saved();mutate(RevisionChanges.Resource.RECORDING,recording,"UPDATE recording SET note='only note' WHERE id=?");
        assertThat(count()).isEqualTo(1);
    }
}
