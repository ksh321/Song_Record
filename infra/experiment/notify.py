"""Fixed, deduplicated experiment alerts. Never log the private topic or server response."""
import json
import os
from pathlib import Path
import re
import urllib.request
from observe import atomic

ROOT = Path('/opt/song-record-experiment/operations')
CONFIG = Path('/etc/song-record-experiment/monitoring.json')
MESSAGES = {
    'CostNotice': 'R2 예상 월 비용이 5만원 이상입니다. 비용 감시 기록에서 사용량을 확인해 주세요. 실제 청구 상한을 보장하지 않습니다.',
    'CostWarning': 'R2 예상 월 비용이 6만원 이상입니다. 저장·요청 증가를 확인하고 불필요한 사용을 줄여 주세요. 실제 청구 상한을 보장하지 않습니다.',
    'CostLock': 'R2 예상 월 비용이 7만원 이상으로 신규 업로드 예약을 잠갔습니다. 기존 저장·읽기 비용은 계속 발생합니다. 비용 감시 기록을 확인해 주세요.',
    'CostUnknown': '비용 자동 조회가 실패했습니다. 마지막 정상 조회 후 26시간이 지나면 신규 업로드가 차단됩니다. 현재 대화에 비용 감시 오류 확인이라고 알려 주세요. 키를 다시 입력하지 마세요.',
    'Trial': '시험 알림입니다. 휴대폰 수신 여부를 대화에 알려주세요.',
    'OperationsWarning': '운영 백업·삭제 원장·관측 또는 월간 복구 점검에 실패·기한 초과가 있습니다. 현재 대화에 운영 점검 오류 확인이라고 알려 주세요. 키를 다시 입력하지 마세요. 자세한 근거는 보호된 operational-checks/latest.json에 저장했습니다.',
}


def send(kind, key):
    if os.getuid() != 0 or kind not in MESSAGES or not re.fullmatch(r'[A-Za-z0-9_.-]{1,100}', key):
        raise ValueError('EXPERIMENT_ALERT_SCOPE_REJECTED')
    path = ROOT / ('notification-' + key + '.json')
    if path.exists():
        return json.loads(path.read_text())['status']
    topic = json.loads(CONFIG.read_text())['ntfy_topic']
    if not re.fullmatch(r'sr-[0-9a-f]{48}', topic):
        raise ValueError('EXPERIMENT_ALERT_TOPIC_REJECTED')
    # An unknown outcome remains attempted; automatic retries cannot duplicate the same event.
    atomic(path, {'kind': kind, 'status': 'ATTEMPTED', 'phone_receipt': 'UNCONFIRMED'})
    data = json.dumps({'topic': topic, 'title': 'P25-06', 'message': MESSAGES[kind], 'priority': 5}).encode()
    client = urllib.request.build_opener(urllib.request.ProxyHandler({}))
    with client.open(urllib.request.Request('https://ntfy.sh', data=data,
                     headers={'Content-Type': 'application/json'}), timeout=20) as reply:
        if reply.status != 200:
            raise ValueError('EXPERIMENT_ALERT_DELIVERY_UNCONFIRMED')
        raw = reply.read(16385)
    if len(raw) > 16384:
        raise ValueError('EXPERIMENT_ALERT_DELIVERY_UNCONFIRMED')
    receipt = json.loads(raw)
    if receipt.get('event') != 'message' or receipt.get('topic') != topic or not isinstance(receipt.get('id'), str) or not receipt['id']:
        raise ValueError('EXPERIMENT_ALERT_DELIVERY_UNCONFIRMED')
    atomic(path, {'kind': kind, 'status': 'SERVER_ACCEPTED', 'phone_receipt': 'UNCONFIRMED',
                  'message_id': receipt['id'], 'server_time': receipt.get('time')})
    return 'SERVER_ACCEPTED'
