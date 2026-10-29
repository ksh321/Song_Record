/* UI proposal adapter. All data and state changes below are local sample state. */
(() => {
  'use strict';
  const F = window.FLOW, R = window.RENDER, P = window.PROJECT;
  const e = R.esc, ic = R.icon;
  const state = { period: '월간', chartState: 'normal', width: 390, large: false,
    list: 'playlist-detail', selected: new Set(), pickQuery: '', reorder: null,
    classKind: '태그', classDraft: null, classEdit: null,
    tags: ['고음', '호흡', '발음'], conditions: ['좋음', '보통', '피곤함'],
    archived: { 태그: [], 컨디션: [] }, sync: 'complete', play: false, position: 0,
    recordId: 'r2', recording: false, seconds: 0, note: '', newList: 0 };
  const mainScreens = [ ['songs','내 곡','music'],['charts','인기 차트','chart'],['record','녹음','mic'],['playlists','플레이리스트','list'],['search','검색','search'],['recordings','전체 녹음','wave'],['settings','설정','settings'] ];
  const uiButton = (label, action, attrs = '', cls = 'command secondary') => `<button type="button" class="${cls}" data-ui="${action}" ${attrs}>${e(label)}</button>`;
  const routeButton = (label, to, cls='command secondary') => `<button type="button" class="${cls}" data-to="${to}">${e(label)}</button>`;
  const row = (title, sub, to, icon='music') => R.block({type:'row',title,sub,to,icon});
  const form = body => `<form class="x-form" onsubmit="return false">${body}<p class="v2-action-error" role="alert"></p></form>`;
  const input = (label, name, value='', max=200) => `<label>${e(label)}<input name="${name}" value="${e(value)}" maxlength="${max}" autocomplete="off"></label>`;
  const select = (label, name, options, value) => `<label>${e(label)}<select name="${name}">${options.map(v=>`<option ${v===value?'selected':''}>${e(v)}</option>`).join('')}</select></label>`;
  const actions = (save, action) => `<div class="v2-form-actions">${uiButton('취소','back')}${uiButton(save,action,'','command primary')}</div>`;
  const raw = html => ({type:'liveHTML',html});
  function addScreen(id,name,tab='songs',back='settings') {
    const screen = {id,name,tab,back,group:'UI 시안 01 보완',blocks:[],rule:'샘플 데이터에서 화면과 조작 흐름을 확인합니다. 실제 인증·마이크·업로드·파일 처리는 실행하지 않습니다.'};
    F.addScreen(screen); window.Prototype.map.set(id,screen);
  }
  for (const [id,name,tab,back] of [
    ['v2-personal','개인화와 분류','songs','settings'],['v2-class','태그 관리','songs','v2-personal'],['v2-class-edit','이름 변경','songs','v2-class'],
    ['v2-sync','동기화 상태','songs','settings'],['v2-delete-status','계정 삭제 상태','songs','account-delete'],
    ['v2-list-menu','목록 관리','playlists','playlists'],['v2-list-name','이름 변경','playlists','v2-list-menu'],
    ['v2-list-order','순서 변경','playlists','v2-list-menu'],['v2-list-remove','목록에서 곡 제거','playlists','v2-list-menu'],
    ['v2-list-delete','플레이리스트 삭제','playlists','v2-list-menu'],['v2-pick-list','내 곡에서 선택','playlists','playlists'],
    ['v2-playback','녹음 듣기','record','recordings'],['v2-recording','녹음 중','record','record'],
    ['v2-record-manage','보관과 파일 관리','record','recordings'],['v2-manual','직접 등록','search','search'],
    ['v2-backup-status','백업과 복원 상태','songs','backup'],
    ['v2-restore-blocked','복원할 수 없는 기록','songs','backup'],
    ['v2-restore-paused','복원 일시 중단','songs','backup'],
    ['v2-delete-delayed','삭제 처리 지연','songs','v2-delete-status'],
    ['v2-draft-tags','컨디션과 태그','record','draft'],['v2-draft-note','연습 메모','record','draft']
  ]) addScreen(id,name,tab,back);
  // More rows make list density and all six chart selections reviewable.
  for(const c of [
    ['04568','너의 계절','이든','TJ'],['04569','오래된 편지','서우','TJ'],['04570','우리의 밤','민재','TJ'],
    ['90124','밤 산책','윤서','금영'],['90125','푸른 계절','하린','금영'],['90126','너의 계절','이든','금영'],['90127','우리의 밤','민재','금영']
  ]) F.catalog.set(c[3]+':'+c[0],{number:c[0],title:c[1],artist:c[2],brand:c[3]});
  const go = id => window.Prototype.go(id);
  const render = () => window.Prototype.render();
  const current = () => window.Prototype.state.screen;
  const error = message => {const target=document.querySelector('.device-holder .v2-action-error');if(target)target.textContent=message;};
  F.freshManualRegistration=()=>({title:'',artist:'',version:'일반 반주',key:'미정',tier:'미정',note:'',suitable:false});
  F.manualRegistration=F.freshManualRegistration();
  const data = () => new FormData(document.querySelector('.device-holder .x-form'));
  const list = () => F.playlists.get(state.list);
  const titleOf = item => F.songs.get(item.songId)?.title || item.candidate?.title || F.catalog.get('TJ:'+item.key.slice(3))?.title || '곡';
  const group = rows => `<div class="v2-settings-group">${rows.join('')}</div>`;
  const empty = (title, description, icon='music') => `<div class="v2-empty">${ic(icon,34)}<strong>${e(title)}</strong><p>${e(description)}</p></div>`;
  const originalSaveDraft=F.saveDraft;
  F.saveDraft=function(){const r=originalSaveDraft();if(r&&F.draft)r.tags=[...(F.draft.tags||[])];return r;};

  function charts(screen) {
    const brand=screen.id==='charts-ky'?'금영':'TJ';
    const candidates=[...F.catalog.values()].filter(c=>c.brand===brand);
    const offset=['월간','주간','일간'].indexOf(state.period);
    const rows=candidates.slice(offset).concat(candidates.slice(0,offset));
    const controls=`<div class="review-brand-tabs">${['TJ','금영'].map(b=>`<button type="button" data-to="${b==='TJ'?'charts':'charts-ky'}" class="${b===brand?'selected':''}" aria-pressed="${b===brand}">${b}</button>`).join('')}</div><div class="v2-periods" aria-label="차트 기간">${['일간','주간','월간'].map(p=>uiButton(p,'period',`data-period="${p}" aria-pressed="${p===state.period}"`,'')).join('')}</div>`;
    if(state.chartState==='error') return controls+empty('차트를 불러오지 못했어요','연결을 확인하고 다시 시도해 주세요.','cloud')+uiButton('다시 시도','chart-retry','','command primary');
    if(state.chartState==='empty') return controls+empty('아직 차트가 없어요','다른 기간을 선택해 보세요.','chart');
    if(state.chartState==='loading') return controls+empty('차트를 불러오고 있어요','잠시만 기다려 주세요.','clock');
    return controls+`<div class="v2-chart-heading"><strong>${state.period} 인기곡</strong><small>최근 갱신 · 오늘 09:00</small></div><div class="v2-chart-rows">`+rows.map((c,i)=>`<button type="button" class="review-ranked" data-flow="candidate" data-candidate="${c.brand}:${c.number}"><span class="review-rank ${i<3?'top':''}">${i+1}</span><span class="review-result-copy"><strong>${e(c.title)}</strong><small>${e(c.artist)}</small></span><span class="review-result-number">${e(c.number)}</span></button>`).join('')+'</div>';
  }
  function settings() {
    return `<div class="v2-profile"><span class="v2-avatar">${ic('people',23)}</span><div><strong>나의 노래기록</strong><small>카카오 계정으로 연결됨</small></div></div><p class="v2-section-title">내 기록 관리</p>`+
    group([row('보관량과 고정','184 MB 사용 · 고정 3개','storage','cloud'),row('백업 내보내기','내 기록을 파일로 보관','backup-export','file'),row('백업 가져오기','백업 파일에서 복원','backup-import','file'),row('휴지통','삭제한 기록 복원','x-trash','trash')])+
    `<p class="v2-section-title">앱 설정</p>`+group([row('개인화와 분류','강조색 · 컨디션 · 태그','v2-personal','palette'),row('동기화 상태','모든 변경사항 반영됨','v2-sync','cloud')])+
    `<p class="v2-section-title">계정</p>`+group([row('로그인 계정 연결','Google · 카카오','account','link'),row('로그아웃','','logout-confirm','logout'),row('계정 탈퇴','','account-delete','personRemove')]);
  }
  function recorder() {
    return `<div class="v2-record-intro"><h3>오늘의 목소리를 남겨요</h3><p>부르고, 듣고, 다음 연습을 준비해요.</p></div><div class="v2-timer">00:00</div><div class="record-control-wrap"><button type="button" class="record-control" data-ui="record-start" aria-label="녹음 시작"><span class="record-control-ring" aria-hidden="true"><span class="record-control-shape circle"></span></span><strong>녹음 시작</strong></button></div><p class="v2-record-footnote">한 번에 최대 6분</p>`+row('입력 대기','곡 정보를 기다리는 녹음 1개','pending','clock')+row('전체 녹음','지난 녹음 다시 듣기','recordings','wave');
  }
  function playback() {
    const r=F.recordings.get(state.recordId)||F.recordings.get('r2');const d=r.duration;
    return `<div class="empty-state"><span class="empty-icon">${ic('wave',28)}</span><strong>${e(r.title)}</strong><p>${e(r.artist)} · ${e(r.version)} · ${e(r.key)}</p></div>`+R.block({type:'wave'})+`<div class="v2-timer" data-play-time>${F.renderHelpers.duration(state.position)}</div><label class="v2-note">재생 위치<input type="range" aria-label="재생 위치" data-seek min="0" max="${d}" value="${state.position}" style="width:100%;accent-color:var(--accent)"></label><p class="v2-note">전체 ${F.renderHelpers.duration(d)}</p>`+uiButton(state.play?'일시 정지':'재생', 'play', '', 'command primary')+routeButton('M4A 내보내기','export-file');
  }
  function supplemental(screen) {
    const id=screen.id;
    if(id==='settings')return settings();
    if(['charts','charts-ky'].includes(id))return charts(screen);
    if(id==='record')return recorder();
    if(id==='v2-recording')return `<div class="v2-record-intro"><h3>목소리를 담고 있어요</h3><p>화면을 잠가도 녹음은 이어져요.</p></div><div class="v2-timer" data-record-time>${F.renderHelpers.duration(state.seconds)}</div>`+R.block({type:'wave'})+`<div class="record-control-wrap"><button type="button" class="record-control" data-ui="record-stop" aria-label="녹음 완료"><span class="record-control-ring"><span class="record-control-shape square"></span></span><strong>녹음 완료</strong></button></div><p class="v2-record-footnote">6분이 되면 자동으로 마무리해요.</p>`;
    if(id==='storage')return `<section class="v2-storage"><h3>서버 보관량</h3><div class="v2-usage">184 MB<small>/ 1 GB</small></div><div class="v2-meter" role="meter" aria-label="서버 보관량" aria-valuenow="184" aria-valuemin="0" aria-valuemax="1000"><span></span></div><p>고정 보관 3 / 10개 · 업로드 대기 6 MB</p></section>`+group([row('고정한 녹음','중요한 녹음을 계속 보관','pin-limit','pin'),row('서버 사본 정리','이 기기의 원본은 유지','server-clean','cloud'),row('자동 보관 기준','대표 · 최신 · 최저 티어','auto-storage','list')])+`<details><summary>사용량 자세히 보기</summary><p>휴지통 20 MB · 정리 대기 14 MB<br>서버 보관량과 기기 저장 공간은 각각 관리돼요.</p></details>`;
    if(id==='v2-personal')return group([row('강조색','7가지 색상에서 선택','accent','palette'),row('컨디션 관리',state.conditions.join(' · '),'v2-class','wave'),row('태그 관리',state.tags.join(' · '),'v2-class','list')]);
    if(id==='v2-class'){
      const kind=state.classKind, entries=kind==='태그'?state.tags:state.conditions;
      return `<p class="v2-note">자주 쓰는 ${kind}${kind==='태그'?'를':'을'} 준비해 두세요. 삭제해도 기존 녹음의 표시는 유지돼요.</p><div>${entries.map((v,i)=>`<div class="v2-class-row"><span>${e(v)}</span><button type="button" data-ui="class-edit" data-index="${i}" aria-label="${e(v)} 이름 변경">${ic('edit',18)}</button><button type="button" data-ui="class-delete" data-index="${i}" aria-label="${e(v)} 삭제">${ic('trash',18)}</button></div>`).join('')}</div>`+form(`<label>새 ${kind}</label><div class="v2-add-row"><input name="className" aria-label="새 ${kind}" maxlength="30" placeholder="이름 입력">${uiButton('추가','class-add','','')}</div>`);
    }
    if(id==='v2-class-edit')return form(input('이름','className',state.classEdit?.value||'',30)+actions('저장','class-save'));
    if(id==='v2-sync')return `<div class="v2-state">${ic(state.sync==='complete'?'check':'cloud',29)}<strong>${state.sync==='complete'?'모두 반영됐어요':'연결을 기다리고 있어요'}</strong><p>${state.sync==='complete'?'마지막 동기화 · 방금 전':'기기에 저장한 변경사항은 연결되면 반영돼요.'}</p></div>`+uiButton('다시 동기화','sync','','command primary')+row('확인이 필요한 변경','이 기기와 서버의 값이 달라요','conflict','edit')+`<details><summary>정보와 녹음 파일</summary><p>곡·메모 등 정보의 동기화와 녹음 파일의 서버 보관은 별개예요. 녹음 파일은 각 녹음 상세에서 확인해 주세요.</p></details>`;
    if(id==='v2-delete-status')return `<div class="v2-state">${ic('clock',28)}<strong>삭제 요청을 처리하고 있어요</strong><p>처리가 완료될 때까지 상태를 확인할 수 있어요.</p></div>`+routeButton('처리 상태 새로고침','account-delete-pending')+routeButton('예정 기한이 지났어요','v2-delete-delayed');
    if(id==='v2-delete-delayed')return `<div class="v2-state"><strong>삭제 처리가 지연되고 있어요</strong><p>요청은 보존되어 있어요. 잠시 후 상태를 다시 확인해 주세요.</p></div>`+routeButton('다시 확인','v2-delete-status')+`<p class="v2-note">계속 지연되면 happycompanyhaha@gmail.com으로 요청 시각과 표시된 오류를 알려 주세요.</p>`;
    if(id==='playlist-create')return form(input('플레이리스트 이름','listName','',100)+actions('만들기','list-create'));
    if(id==='v2-list-name')return form(input('플레이리스트 이름','listName',list()?.title||'',100)+actions('저장','list-rename'));
    if(id==='v2-list-menu')return group([row('이름 변경',list()?.title||'','v2-list-name','edit'),row('순서 변경','목록에 담은 순서 조정','v2-list-order','list'),row('곡 제거','이 목록에서만 제거','v2-list-remove','minus')])+routeButton('플레이리스트 삭제','v2-list-delete','command danger');
    if(id==='v2-list-delete')return `<div class="v2-state"><strong>${e(list()?.title)}</strong><p>이 플레이리스트를 삭제할까요?<br>내 곡과 녹음은 그대로 남아요.</p></div>`+uiButton('목록 삭제','list-delete','','command danger')+uiButton('취소','back');
    if(id==='v2-list-order'){
      const items=state.reorder||list()?.items||[];
      return `<p class="v2-note">위아래 버튼으로 순서를 바꾸고 저장해 주세요.</p>`+items.filter(v=>!v.hiddenBy).map((item,i)=>`<div class="v2-class-row"><span>${i+1}. ${e(titleOf(item))}</span>${uiButton('↑','list-move',`data-index="${i}" data-direction="-1" aria-label="${e(titleOf(item))} 위로" ${i===0?'disabled':''}`,'')}${uiButton('↓','list-move',`data-index="${i}" data-direction="1" aria-label="${e(titleOf(item))} 아래로" ${i===items.length-1?'disabled':''}`,'')}</div>`).join('')+actions('순서 저장','list-order-save');
    }
    if(id==='v2-list-remove')return `<p class="v2-note">이 목록에서만 제거돼요. 내 곡과 녹음은 유지돼요.</p>`+(list()?.items.filter(v=>!v.hiddenBy).map(item=>`<div class="v2-class-row"><span>${e(titleOf(item))}</span>${uiButton('제거','list-remove',`data-id="${item.id}"`,'')}</div>`).join('')||empty('목록이 비어 있어요','새로운 곡을 담아 보세요.'))+uiButton('완료','list-return','','command primary');
    if(id==='v2-pick-list'){
      const own=list(),songs=F.activeSongs(state.pickQuery);
      return `<label class="review-query flow-query">${ic('search',18)}<input data-pick-query type="search" value="${e(state.pickQuery)}" placeholder="곡명 또는 가수 검색" aria-label="곡명 또는 가수 검색"></label><p class="v2-note">${e(own?.title)} · ${state.selected.size}곡 선택</p>`+songs.map(s=>{const exists=own?.items.some(i=>i.key===s.id);return `<button type="button" class="compact-row" data-ui="list-pick" data-song="${s.id}" aria-pressed="${state.selected.has(s.id)}" ${exists?'disabled':''}><span class="tier">${exists?'✓':state.selected.has(s.id)?'✓':'+'}</span><span class="compact-copy"><strong>${e(s.title)}</strong><small>${e(s.artist+' · '+s.version)}</small></span><span class="flow-already">${exists?'추가됨':state.selected.has(s.id)?'선택됨':''}</span></button>`;}).join('')+(!songs.length?empty('검색 결과가 없어요','다른 곡명이나 가수를 입력해 보세요.'):``)+uiButton(`${state.selected.size}곡 추가`,'list-pick-save',state.selected.size?'':'disabled','command primary')+uiButton('취소','back');
    }
    if(id==='v2-playback')return playback();
    if(id==='v2-record-manage'){
      const r=F.recordings.get(state.recordId)||F.recordings.get('r2');
      return `<div class="v2-state"><strong>${e(r.title)}</strong><p>${e(X.fileState(r))}</p></div>`+uiButton(r.pinned?'고정 해제':'고정 보관','pin','','command primary')+routeButton('이 기기의 파일 정리','local-clean')+routeButton('M4A 내보내기','export-file')+routeButton('녹음 삭제','record-delete','command danger');
    }
    if(id==='v2-manual'){
      const d=F.manualRegistration,picker=(kind,title)=>R.block({type:'editField',source:id,scope:'manual',kind,title,value:d[kind]});
      return form(input('곡명','title',d.title)+input('가수','artist',d.artist)+picker('version','버전')+picker('key','대표 키')+picker('tier','곡 티어')+`<label>메모<textarea name="note" maxlength="2000">${e(d.note)}</textarea></label>`+actions('내 곡 등록','manual-save'));
    }
    if(id==='v2-backup-status')return group([row('일부 파일 누락','백업에서 빠진 파일 확인','backup-partial','file'),row('복원 전 확인','추가·중복·충돌 항목 확인','import-preview','check'),row('중단된 복원','처리한 항목을 유지하고 이어서 복원','v2-restore-paused','clock'),row('서버에서 삭제된 기록','삭제된 기록은 다시 복원하지 않아요','v2-restore-blocked','people')]);
    if(id==='v2-restore-blocked')return `<div class="v2-state"><strong>일부 기록은 복원할 수 없어요</strong><p>서버에서 이미 삭제된 기록은 백업에 있어도 다시 복원되지 않아요.</p></div>`+routeButton('복원 가능한 항목 확인','import-preview','command primary')+routeButton('돌아가기','backup');
    if(id==='v2-restore-paused')return `<div class="v2-state"><strong>복원을 잠시 멈췄어요</strong><p>완료한 3개 항목은 유지돼요.<br>남은 항목부터 이어서 복원할 수 있어요.</p></div>`+routeButton('이어서 복원','import-done','command primary')+routeButton('나중에 하기','backup');
    if(id==='v2-draft-tags'){
      const d=F.ensureDraft(F.screenMap.get('draft'));
      const available=[...new Set([...state.tags,...(d.tags||[])])];
      return form(select('컨디션','condition',['선택 안 함',...state.conditions,...(state.archived.컨디션.includes(d.condition)?[d.condition]:[])],d.condition)+`<fieldset><legend>태그</legend>${available.map(t=>`<label><input type="checkbox" name="tags" value="${e(t)}" ${(d.tags||[]).includes(t)?'checked':''}>${e(t)}</label>`).join('')}</fieldset>`+actions('적용','draft-tags-save'));
    }
    if(id==='v2-draft-note')return form(`<label>연습 메모<textarea name="note" maxlength="2000" placeholder="다음 연습에 기억하고 싶은 것">${e(F.draft?.note||'')}</textarea></label><p class="v2-note">최대 2,000자</p>`+actions('적용','draft-note-save'));
    return null;
  }

  const basePhone=R.phone;
  R.phone=function(screen,interactive=true){
    let html=basePhone(screen,interactive);
    // Parse only our own local markup to keep every existing handler and data attribute.
    const template=document.createElement('template');template.innerHTML=html;
    const phone=template.content.querySelector('.phone');if(!phone)return html;
    const content=phone.querySelector('.phone-body');
    const custom=supplemental(screen);if(custom!==null)content.innerHTML=custom;
    const heading=phone.querySelector('.phone-header h2');
    if(screen.id==='v2-class')heading.textContent=state.classKind+' 관리';
    if(screen.id==='recordings')heading.textContent='전체 녹음';
    if(screen.id==='storage')heading.textContent='보관량과 고정';
    if(screen.id==='charts'||screen.id==='charts-ky'){
      phone.querySelector('.phone-header p')?.remove();
      content.style.gap='0';
    }
    // Fix record metadata hierarchy without hiding availability or failed states.
    for(const badge of phone.querySelectorAll('.tier'))badge.dataset.tier=badge.textContent.trim();
    for(const badge of phone.querySelectorAll('.key')){
      badge.textContent=badge.textContent.replace(/^([남여])\s+[+-]?0$/,'$1');
      badge.classList.toggle('male',badge.textContent.trim().startsWith('남'));
      badge.classList.toggle('female',badge.textContent.trim().startsWith('여'));
    }
    for(const notice of phone.querySelectorAll('.notice')){
      notice.innerHTML=notice.innerHTML.replace('표본 검색 결과가 없어요.','검색 결과가 없어요.').replace(' 이 미리보기는 세션 내 복원을 시연해요.','');
    }
    const listId=F.listScreens.get(screen.id);
    if(listId&&F.playlists.has(listId)){
      phone.querySelectorAll('[data-to="playlist-menu"]').forEach(b=>{b.removeAttribute('data-to');b.dataset.ui='list-menu';b.dataset.list=listId;});
      if(!phone.querySelector('[data-ui="list-menu"]'))content.insertAdjacentHTML('beforeend',uiButton('목록 관리','list-menu',`data-list="${listId}"`));
    }
    if(F.recordFor(screen)){
      const rec=F.recordFor(screen);
      phone.querySelectorAll('[data-to="playback"],[data-to="playback-recent"]').forEach(b=>{b.removeAttribute('data-to');b.dataset.ui='play-open';b.dataset.record=rec.id;});
      phone.querySelectorAll('[data-to="record-manage"]').forEach(b=>{b.removeAttribute('data-to');b.dataset.ui='record-manage';b.dataset.record=rec.id;});
      const status=content.querySelector('.notice');
      if(status&&status.textContent.includes('정보 동기화:'))status.outerHTML=`<details class="v2-file-status"><summary>${e(X.fileState(rec))}</summary><p>정보 동기화 · 완료<br>기기 파일 · ${rec.local?'있음':'없음'}<br>서버 파일 · ${e(rec.cloud)}</p></details>`;
    }
    phone.querySelectorAll('[data-to="manual-register"]').forEach(b=>b.dataset.to='v2-manual');
    phone.querySelectorAll('[data-flow="playlist-picker"]').forEach(b=>{delete b.dataset.flow;b.dataset.ui='list-picker';});
    if(screen.name==='녹음 정보 입력'){
      for(const field of content.querySelectorAll('.field')){
        const label=field.querySelector('small')?.textContent;
        if(label==='컨디션·태그'){field.outerHTML=`<button type="button" class="field" data-to="v2-draft-tags"><span class="field-copy"><small>컨디션·태그</small><strong>${e([F.draft?.condition||'선택 안 함',...(F.draft?.tags||[])].join(' · '))}</strong></span>${ic('chevron',16)}</button>`;}
        if(label==='연습 메모'){field.outerHTML=`<button type="button" class="field" data-to="v2-draft-note"><span class="field-copy"><small>연습 메모</small><strong>${e(F.draft?.note||'아직 입력하지 않았어요.')}</strong></span>${ic('chevron',16)}</button>`;}
      }
    }
    if(screen.id==='x-record-edit'||screen.id==='record-filter'){
      const condition=content.querySelector('select[name="condition"]');
      if(condition){const old=condition.value;const values=[...(screen.id==='record-filter'?['']:[]),'선택 안 함',...state.conditions,...state.archived.컨디션.filter(v=>v===old)];condition.innerHTML=values.map(v=>`<option value="${e(v)}" ${v===old?'selected':''}>${e(v||'전체')}</option>`).join('');}
      const fieldset=content.querySelector('fieldset');
      if(fieldset){const checked=[...fieldset.querySelectorAll('input:checked')].map(n=>n.value);fieldset.innerHTML='<legend>태그</legend>'+[...new Set([...state.tags,...checked])].map(v=>`<label><input type="checkbox" name="tags" value="${e(v)}" ${checked.includes(v)?'checked':''}>${e(v)}</label>`).join('');}
      const tag=content.querySelector('select[name="tag"]');if(tag){const old=tag.value;tag.innerHTML=['',...state.tags,...state.archived.태그].map(v=>`<option value="${e(v)}" ${v===old?'selected':''}>${e(v||'전체')}</option>`).join('');}
    }
    if(screen.id==='account-delete-pending')content.insertAdjacentHTML('beforeend',routeButton('삭제 처리 상태 확인','v2-delete-status'));
    if(screen.id==='backup')content.insertAdjacentHTML('beforeend',routeButton('복원 결과와 예외 확인','v2-backup-status'));
    if(F.editorScreens.has(screen.id)&&!content.querySelector('[data-ui="back"]'))content.insertAdjacentHTML('beforeend',uiButton('취소','back'));
    // Native system / account actions remain clearly labeled mock flows in the workbench.
    phone.querySelectorAll('.phone-nav button').forEach(b=>b.setAttribute('aria-current',b.classList.contains('active')?'page':'false'));
    return template.innerHTML;
  };

  const notes={
    songs:['곡명과 가수를 먼저 읽고, 티어·키는 작은 배지로 확인해요.','검색·보기 전환·정렬·새 곡 찾기를 유지했어요.','곡을 눌러 상세와 수정 화면까지 확인해 보세요.'],
    charts:['TJ·금영과 일간·주간·월간을 바로 바꿀 수 있어요.','순위·곡명·가수·번호를 한 줄 묶음으로 정리했어요.','아래로 스크롤하면 작은 버튼으로 맨 위로 돌아갈 수 있어요.'],
    record:['녹음 시작이 가장 먼저 보이는 행동이에요.','입력 대기와 전체 녹음은 아래에서 이어가요.','타이머·완료·곡 선택·나중에 입력 흐름을 확인해 보세요.'],
    playlists:['목록과 곡을 삭제하는 동작을 구분했어요.','이름·순서 변경, 다중 선택과 취소를 눌러볼 수 있어요.','미등록 후보와 중복 추가 방지 흐름도 유지했어요.'],
    search:['제공자 → 검색어 → 검색 종류 순서로 읽혀요.','금영 결과는 TJ에서 찾아 등록하는 흐름을 유지해요.','검색 실패·빈 결과·직접 등록도 확인할 수 있어요.'],
    settings:['기록 관리·앱 설정·계정으로 나눴어요.','분류 관리·동기화·계정 연결을 빠뜨리지 않았어요.','서버·파일 처리와 실제 인증은 기존 베타 앱에서 확인해요.'],
    recordings:['제목·가수·날짜·키·버전·파일 상태를 유지했어요.','필터는 적용·초기화·취소를 구분해요.','목록에서 상세·편집·재생으로 이어져요.']
  };
  let noteStore={};try{noteStore=JSON.parse(localStorage.getItem('song-record-v2-review')||'{}');}catch{}
  function screenGroup(id){
    if(id==='charts-ky')return 'charts';
    if(id.startsWith('v2-list')||id==='v2-pick-list')return 'playlists';
    return mainScreens.some(([key])=>key===id)?id:F.screenMap.get(id)?.tab||'settings';
  }
  const previousAfter=window.EDIT_UI.afterRender;
  window.EDIT_UI.afterRender=function(goFn,renderFn,id){
    previousAfter(goFn,renderFn,id);
    document.body.classList.toggle('large-text',state.large);
    document.documentElement.style.setProperty('--preview-width',state.width+'px');
    document.querySelector('#screen-count').textContent='샘플 데이터로 직접 눌러보고, 화면별로 다듬는 시안';
    if(window.Prototype?.state.mode!=='prototype')return;
    const screen=F.screenMap.get(id),section=screenGroup(id);
    document.querySelector('.sidebar').innerHTML=`<p class="eyebrow">화면 둘러보기</p>`+mainScreens.map(([key,label,icon],i)=>`<button type="button" class="scenario ${section===key?'active':''}" data-jump="${key}">${ic(icon,18)}<span>${label}</span><span class="side-index">0${i+1}</span></button>`).join('')+`<hr><label class="scenario-label" for="review-scenario">추가 흐름</label><select class="scenario-select" id="review-scenario"><option value="">확인할 흐름 선택</option>${[['song-detail','곡 상세 / 편집'],['record-detail','녹음 상세 / 편집'],['record-filter','녹음 필터'],['pending','입력 대기'],['x-trash','휴지통 / 복원'],['backup','백업 / 복원'],['v2-personal','개인화 / 분류'],['v2-sync','동기화 / 충돌'],['account','계정 연결'],['account-delete','계정 탈퇴'],['login','로그인'],['search-error','검색 오류'],['mic-denied','녹음 권한 거부'],['pin-limit','고정 한도'],['cloud-quota','보관량 부족']].map(([value,label])=>`<option value="${value}">${label}</option>`).join('')}</select><p class="sidebar-note">앱 안의 버튼으로도 이동할 수 있어요.<br>색상과 화면 구조를 하나씩 정해 보세요.</p><a class="foot-link" href="coverage.md" target="_blank" rel="noopener">기능 대조표 ↗</a>`;
    const tips=notes[section]||notes.settings;
    const modeNote=id==='v2-recording'?'타이머와 저장 흐름만 시연하며 마이크를 사용하지 않아요.':id==='v2-playback'?'재생 조작을 시연해요. 샘플 음원은 포함되지 않아 소리는 나지 않아요.':/login|account|backup|export|import|delete|purge/.test(id)?'인증·백업·삭제 결과는 화면 시연이에요. 실제 계정이나 파일을 처리하지 않아요.':'검색·편집·목록 변경은 이 탭 안의 샘플에만 적용돼요. 새로고침하면 초기화돼요.';
    document.querySelector('.inspector').innerHTML=`<p class="review-kicker">DESIGN REVIEW · 02</p><h2>${e(screen?.name||'화면 검토')}</h2><div class="state-id">${e(id)}</div><ul class="review-changes">${tips.map(t=>`<li>${e(t)}</li>`).join('')}</ul><h3>이 화면에서 바꾸고 싶은 점</h3><textarea class="review-note" id="review-note" placeholder="예: 곡명 더 크게 / 이 버튼 위로 / 설명 줄이기" aria-label="화면 수정 메모">${e(noteStore[id]||'')}</textarea><div class="review-saved" role="status">${noteStore[id]?'이 브라우저에 저장됨':'입력하면 이 브라우저에 저장돼요.'}</div><button class="review-export" data-ui="export-notes">전체 메모 내려받기</button><h3>화면 너비</h3><div class="viewport-options">${[360,390,430].map(w=>uiButton(w+' px','width',`data-width="${w}" aria-pressed="${state.width===w}"`,'')).join('')}</div><h3>강조색</h3><div class="legend">${P.palettes.map(([n,c],i)=>`<button type="button" title="${n}" aria-label="시안 강조색 ${n}" data-accent="${i}" style="--swatch:${c}"></button>`).join('')}</div>${section==='charts'?`<label class="scenario-label" for="chart-state">차트 상태</label><select id="chart-state" class="scenario-select">${[['normal','목록'],['loading','불러오는 중'],['empty','빈 결과'],['error','연결 실패']].map(([value,label])=>`<option value="${value}" ${state.chartState===value?'selected':''}>${label}</option>`).join('')}</select>`:''}<p class="disclaimer"><strong>실제 앱과 연결되지 않은 시안</strong><br>${modeNote}<br>오른쪽 수정 메모와 강조색은 이 브라우저에 남아요.</p>`;
    document.querySelectorAll('.inspector [data-accent]').forEach(b=>b.setAttribute('aria-pressed',Number(b.dataset.accent)===window.Prototype.state.accent));
    const toolbar=document.querySelector('.stage-toolbar>span');if(toolbar)toolbar.textContent='노래기록 · '+(mainScreens.find(([key])=>key===section)?.[1]||screen?.name);
  };

  // Capture custom controls before the preserved sample engine sees them.
  document.addEventListener('click',ev=>{
    const b=ev.target.closest('button');if(!b||b.disabled)return;
    const d=b.dataset;
    if(d.to==='v2-class')state.classKind=b.textContent.includes('컨디션')?'컨디션':'태그';
    if(d.to==='v2-list-order')state.reorder=list()?.items.filter(i=>!i.hiddenBy).map(i=>({...i}))||[];
    if(d.flow==='playlist-picker'){
      ev.preventDefault();ev.stopImmediatePropagation();state.list=F.ui.context?.playlist||state.list;state.selected.clear();state.pickQuery='';F.close();go('v2-pick-list');return;
    }
    if(d.ui===undefined)return;
    ev.preventDefault();ev.stopImmediatePropagation();
    switch(d.ui){
      case 'back':state.selected.clear();state.reorder=null;window.Prototype.back();break;
      case 'width':state.width=Number(d.width);render();break;
      case 'period':state.period=d.period;state.chartState='normal';render();break;
      case 'chart-retry':state.chartState='normal';render();break;
      case 'record-start':state.seconds=0;state.recording=true;F.makeDraft(F.screenMap.get('draft'));Object.assign(F.draft,{note:'',condition:'선택 안 함',tags:[]});go('v2-recording');break;
      case 'draft-tags-save':{const v=data(),d=F.ensureDraft(F.screenMap.get('draft'));d.condition=String(v.get('condition'));d.tags=v.getAll('tags').map(String);window.Prototype.back();break;}
      case 'draft-note-save':F.ensureDraft(F.screenMap.get('draft')).note=String(data().get('note')||'');window.Prototype.back();break;
      case 'record-stop':state.recording=false;F.ensureDraft(F.screenMap.get('draft'));if(F.draft)F.draft.duration=Math.max(1,state.seconds);go('draft');break;
      case 'play-open':state.recordId=d.record;state.position=0;state.play=false;go('v2-playback');break;
      case 'play':state.play=!state.play;render();break;
      case 'record-manage':state.recordId=d.record;go('v2-record-manage');break;
      case 'pin':{const r=F.recordings.get(state.recordId);if(r){r.pinned=!r.pinned;F.ui.notice=r.pinned?'고정 보관으로 설정했어요.':'고정 보관을 해제했어요.';}render();break;}
      case 'sync':state.sync='complete';F.ui.notice='변경사항을 모두 반영했어요.';render();break;
      case 'list-menu':state.list=d.list;go('v2-list-menu');break;
      case 'list-picker':state.list=F.ui.context?.playlist||state.list;state.selected.clear();state.pickQuery='';F.close();go('v2-pick-list');break;
      case 'list-create':{const name=String(data().get('listName')||'').trim();if(!name){error('플레이리스트 이름을 입력해 주세요.');break;}const id='v2-playlist-'+(++state.newList);F.playlists.set(id,{id,title:name,icon:String(data().get('playlistIcon')||'music'),items:[]});F.listScreens.set(id,id);addScreen(id,name,'playlists','playlists');state.list=id;go(id);break;}
      case 'list-rename':{const name=String(data().get('listName')||'').trim();if(!name){error('이름을 입력해 주세요.');break;}list().title=name;go(state.list);break;}
      case 'list-delete':F.playlists.delete(state.list);F.ui.context=null;go('playlists');break;
      case 'list-return':go(state.list);break;
      case 'list-move':{const n=Number(d.index),to=n+Number(d.direction),a=state.reorder;if(a&&to>=0&&to<a.length){[a[n],a[to]]=[a[to],a[n]];render();}break;}
      case 'list-order-save':if(list()&&state.reorder)list().items=[...state.reorder,...list().items.filter(i=>i.hiddenBy)];state.reorder=null;go(state.list);break;
      case 'list-remove':list().items=list().items.filter(i=>i.id!==d.id);render();break;
      case 'list-pick':state.selected.has(d.song)?state.selected.delete(d.song):state.selected.add(d.song);render();break;
      case 'list-pick-save':for(const key of state.selected)F.addToPlaylist(state.list,key);state.selected.clear();go(state.list);break;
      case 'class-add':{const value=String(data().get('className')||'').trim(),entries=state.classKind==='태그'?state.tags:state.conditions;if(!value){error('이름을 입력해 주세요.');break;}if(entries.includes(value)||state.archived[state.classKind].includes(value)){error('이미 있는 이름이에요.');break;}entries.push(value);render();break;}
      case 'class-edit':{const entries=state.classKind==='태그'?state.tags:state.conditions;state.classEdit={index:Number(d.index),value:entries[Number(d.index)]};go('v2-class-edit');break;}
      case 'class-save':{const value=String(data().get('className')||'').trim(),entries=state.classKind==='태그'?state.tags:state.conditions;if(!value){error('이름을 입력해 주세요.');break;}if(entries.some((n,i)=>n===value&&i!==state.classEdit.index)||state.archived[state.classKind].includes(value)){error('이미 있는 이름이에요.');break;}const previous=state.classEdit.value;entries[state.classEdit.index]=value;for(const r of [...F.recordings.values(),...(F.draft?[F.draft]:[])]){if(state.classKind==='태그')r.tags=(r.tags||[]).map(t=>t===previous?value:t);else if(r.condition===previous)r.condition=value;}go('v2-class');break;}
      case 'class-delete':{const entries=state.classKind==='태그'?state.tags:state.conditions;state.archived[state.classKind].push(...entries.splice(Number(d.index),1));render();break;}
      case 'manual-save':{const value=data(),title=String(value.get('title')||'').trim(),artist=String(value.get('artist')||'').trim();if(!title||!artist){error('곡명과 가수를 입력해 주세요.');break;}const id='manual:v2-'+Date.now();F.songs.set(id,{id,number:null,title,artist,suitable:value.has('suitable'),version:F.manualRegistration.version,key:F.manualRegistration.key,tier:F.manualRegistration.tier,added:Date.now(),active:true,representative:null,note:String(value.get('note')||'')});F.manualRegistration=F.freshManualRegistration();if(F.ui.context?.playlist){const listId=F.ui.context.playlist;F.addToPlaylist(listId,id);go(listId);}else go(F.songRoute(id));break;}
      case 'export-notes':{const entries=Object.entries(noteStore).filter(([,v])=>v.trim());const text='# 노래기록 UI 시안 03 수정 메모\n\n'+entries.map(([id,n])=>`## ${F.screenMap.get(id)?.name||id} (${id})\n${n}`).join('\n\n');const url=URL.createObjectURL(new Blob([text],{type:'text/plain;charset=utf-8'}));const a=document.createElement('a');a.href=url;a.download='노래기록-UI-수정메모.txt';a.click();setTimeout(()=>URL.revokeObjectURL(url),1000);break;}
    }
  },true);
  document.addEventListener('change',ev=>{
    if(ev.target.id==='review-scenario'&&ev.target.value)go(ev.target.value);
    if(ev.target.id==='chart-state'){state.chartState=ev.target.value;render();}
  });
  document.addEventListener('input',ev=>{
    if(ev.target.id==='review-note'){
      noteStore[current()]=ev.target.value;
      try{localStorage.setItem('song-record-v2-review',JSON.stringify(noteStore));document.querySelector('.review-saved').textContent='이 브라우저에 저장됨';}catch{document.querySelector('.review-saved').textContent='저장 공간을 사용할 수 없어요. 메모를 내려받아 주세요.';}
    }
    if(ev.target.hasAttribute('data-pick-query')){state.pickQuery=ev.target.value;render();const field=document.querySelector('[data-pick-query]');field?.focus();}
    if(ev.target.hasAttribute('data-seek')){state.position=Number(ev.target.value);const time=document.querySelector('[data-play-time]');if(time)time.textContent=F.renderHelpers.duration(state.position);}
  });
  setInterval(()=>{
    if(state.recording){state.seconds=Math.min(360,state.seconds+1);const el=document.querySelector('[data-record-time]');if(el)el.textContent=F.renderHelpers.duration(state.seconds);if(state.seconds===360){state.recording=false;F.ensureDraft(F.screenMap.get('draft'));if(F.draft)F.draft.duration=360;go('draft');}}
    if(state.play&&current()==='v2-playback'){const r=F.recordings.get(state.recordId);state.position=Math.min(r?.duration||0,state.position+1);const el=document.querySelector('[data-play-time]'),slider=document.querySelector('[data-seek]');if(el)el.textContent=F.renderHelpers.duration(state.position);if(slider)slider.value=state.position;if(state.position===(r?.duration||0)){state.play=false;render();}}
  },1000);
  P.scenarios.push(['개인화와 분류','v2-personal','강조색·태그·컨디션 추가·이름 변경·숨김과 복원'],['동기화 상태','v2-sync','최근 동기화·재시도·충돌 확인'],['계정 삭제 진행 상태','v2-delete-status','진행·재시도·기한 초과 안내'],['플레이리스트 편집','playlists','생성·이름 변경·순서 저장/취소·제거·다중 선택'],['녹음 재생 조작','record-detail','재생·일시 정지·위치 이동·내보내기 화면']);
  render();
})();

/* PDF feedback, revision 02. Sample-only UI; no service or real file operations. */
(() => {
  'use strict';
  const F=window.FLOW,R=window.RENDER,e=R.esc,icon=R.icon;
  const s={record:'r2',playing:false,position:0,recordList:null,forms:new Map(),classOrigin:null,
    classRename:null,backup:null,importStage:'idle',importTimer:null,drag:null,suppressClick:false,light:localStorage.getItem('song-record-preview-light')==='true'};
  const current=()=>window.Prototype.state.screen;
  const go=id=>window.Prototype.go(id);
  const render=()=>window.Prototype.render();
  const back=()=>window.Prototype.back();
  const button=(label,action,attrs='',cls='command secondary')=>`<button type="button" class="${cls}" data-v3="${action}" ${attrs}>${e(label)}</button>`;
  const note=text=>`<p class="v3-note">${e(text)}</p>`;
  const field=(label,value)=>`<div class="field"><span class="field-copy"><small>${e(label)}</small><strong>${e(value)}</strong></span></div>`;
  const playlistIcons={music:['음표','<path d="M9 18V5l12-2v13M9 9l12-2"/><ellipse cx="6" cy="18" rx="3" ry="3"/><ellipse cx="18" cy="16" rx="3" ry="3"/>'],mic:['마이크','<rect x="9" y="2" width="6" height="13" rx="3"/><path d="M5 10v2a7 7 0 0 0 14 0v-2M12 19v3M8 22h8"/>'],heart:['하트','<path d="M20.8 4.6a5.5 5.5 0 0 0-7.8 0L12 5.7l-1.1-1.1a5.5 5.5 0 0 0-7.8 7.8L12 21l8.8-8.6a5.5 5.5 0 0 0 0-7.8Z"/>'],star:['별','<path d="m12 3 2.8 5.7 6.2.9-4.5 4.4 1.1 6.2-5.6-3-5.6 3 1.1-6.2L3 9.6l6.2-.9Z"/>'],headphones:['헤드폰','<path d="M3 14v-3a9 9 0 0 1 18 0v3"/><rect x="3" y="12" width="4" height="9" rx="2"/><rect x="17" y="12" width="4" height="9" rx="2"/>'],sun:['햇살','<circle cx="12" cy="12" r="4"/><path d="M12 2v2M12 20v2M2 12h2M20 12h2M5 5l1.5 1.5M17.5 17.5 19 19M5 19l1.5-1.5M17.5 6.5 19 5"/>']};
  const playlistGlyph=key=>`<svg width="24" height="24" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.7" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true">${(playlistIcons[key]||playlistIcons.music)[1]}</svg>`;
  const iconPicker=selected=>`<div class="v5-icon-picker"><p>아이콘 <small>선택하지 않으면 음표로 만들어요</small></p><input type="hidden" name="playlistIcon" value="${e(selected||'music')}"><div class="v5-icon-options">${Object.entries(playlistIcons).map(([key,[name]])=>`<button type="button" data-v3="pick-icon" data-icon="${key}" aria-label="${name}" aria-pressed="${key===(selected||'music')}">${playlistGlyph(key)}<small>${name}</small></button>`).join('')}</div></div>`;
  function addScreen(id,name,tab,backTo){const screen={id,name,tab,back:backTo,group:'UI 시안 03 수정',blocks:[],rule:'사용자 PDF 수정안 · 샘플 상태 시연. 실제 음원·서버·파일 처리는 하지 않습니다.'};F.addScreen(screen);window.Prototype.map.set(id,screen);}
  [
    ['v3-record-source','곡 선택','record','draft'],['v3-record-lists','플레이리스트에서 선택','record','v3-record-source'],
    ['v3-record-list','곡 선택','record','v3-record-lists'],['v3-add-source','곡 추가','playlists','playlists'],
    ['v3-backup-file','백업 파일 선택','songs','backup-import'],['v3-import-progress','백업 가져오기','songs','backup-import'],['v5-list-icon','아이콘 수정','playlists','playlists']
  ].forEach(args=>addScreen(...args));
  const keyFor=c=>c?.brand==='TJ'?'tj:'+c.number:null;
  const membership=c=>{
    const key=keyFor(c),own=key?F.songs.get(key):null;
    return {key,own,lists:key?[...F.playlists.values()].filter(p=>p.items.some(i=>i.key===key&&!i.hiddenBy)):[]};
  };
  function membershipText(c){const {own,lists}=membership(c);return [own?.active?'내 곡에 있음':own?'휴지통에 있음':'내 곡 미등록',lists.length?'플리에 담김 · '+lists.map(p=>p.title).join(', '):''].filter(Boolean).join(' · ');}
  function membershipBadge(c){const {own,lists}=membership(c);return c.brand==='TJ'?`<small class="v3-membership">${e([own?.active?'내 곡에 있음':own?'휴지통에 있음':'내 곡 미등록',lists.length?'플리 '+lists.length+'개에 담김':''].filter(Boolean).join(' · '))}</small>`:'';}
  function candidateFor(screen){if(screen.id==='live-candidate')return F.catalog.get(F.ui.candidate);return null;}
  function candidateView(c){
    const {key,own,lists}=membership(c),context=F.ui.context||{},destination=context.playlist&&F.playlists.get(context.playlist);
    const hero=`<section class="v3-song-heading"><span class="v3-eyebrow">${e(c.brand+' '+c.number)}</span><h3>${e(c.title)}</h3><p>${e(c.artist)}</p>${membershipBadge(c)}</section>`;
    if(c.brand!=='TJ')return hero+note('금영 곡은 TJ에서 같은 곡을 찾아 선택해 주세요.')+`<button type="button" class="command primary" data-flow="ky-to-tj" data-candidate="${e(c.brand+':'+c.number)}">TJ에서 이 곡 찾기</button>`;
    if(destination&&context.mode==='add'){
      const exists=destination.items.some(i=>i.key===key&&!i.hiddenBy);
      return hero+`<div class="v3-destination"><small>추가할 플레이리스트</small><strong>${e(destination.title)}</strong></div>`+
        note(exists?'이미 이 플레이리스트에 담겨 있어요.':own?.active?'이 곡을 플레이리스트에 담을까요?':'내 곡에 등록하지 않고 플레이리스트에 먼저 담아요. 나중에 내 곡으로 등록할 수 있어요.')+
        button(exists?'이미 담긴 곡':'플레이리스트에 담기','candidate-add',`data-candidate="${e(c.brand+':'+c.number)}" ${exists?'disabled':''}`,'command primary')+button('취소','back');
    }
    if(context.draft)return hero+note(own?.active?'이 곡에 녹음을 연결해요.':'내 곡으로 등록한 뒤 이 녹음을 연결해요.')+
      button(own?.active?'이 곡 선택':'내 곡 등록하고 연결','register',`data-candidate="${e(c.brand+':'+c.number)}"`,'command primary')+button('취소','back');
    return hero+`<div class="review-choices"><button type="button" class="review-choice" data-v3="register" data-candidate="${e(c.brand+':'+c.number)}"><span class="review-choice-icon">${icon('music',23)}</span><strong>${own?.active?'내 곡 보기':'내 곡 등록'}</strong><small>이 TJ 번호의 곡을 내 곡에 저장</small><span class="review-choice-arrow">${icon('chevron',14)}</span></button><button type="button" class="review-choice" data-v3="candidate-lists" data-candidate="${e(c.brand+':'+c.number)}"><span class="review-choice-icon">${icon('list',23)}</span><strong>플레이리스트에 추가</strong><small>목록을 선택해 담기</small><span class="review-choice-arrow">${icon('chevron',14)}</span></button></div>`;
  }
  function register(c){
    if(!c||c.brand!=='TJ')return;
    const own=F.songs.get(keyFor(c));
    if(own&&!own.active){s.restoreCandidate=c;render();return;}
    if(own?.active){if(F.ui.context?.draft){F.selectSong(own.id);window.Prototype.returnTo(F.ui.context.draft);}else go(F.songRoute(own.id));return;}
    F.registration={candidate:c,values:{version:'일반 반주',key:'미정',tier:'미정'}};go('live-register');
  }
  function addCandidate(listId,c){
    const list=F.playlists.get(listId),key=keyFor(c);if(!list||!key||list.items.some(i=>i.key===key&&!i.hiddenBy))return;
    const own=F.songs.get(key);
    if(own&&!own.active)list.items.push({id:'v3-candidate-'+Date.now()+'-'+list.items.length,key,songId:null,candidate:{...c}});
    else F.addToPlaylist(listId,c);
  }
  const selection=(label,description,action,attrs='',glyph='music')=>`<button type="button" class="v3-source" data-v3="${action}" ${attrs}><span class="v3-source-icon">${icon(glyph,22)}</span><span><strong>${e(label)}</strong><small>${e(description)}</small></span>${icon('chevron',16)}</button>`;
  const titleOf=item=>F.songs.get(item.songId)?.title||item.candidate?.title||F.catalog.get('TJ:'+item.key.slice(3))?.title||'곡';
  function dragRow(kind,id,label,html){return `<div class="v3-draggable" data-drag-kind="${kind}" data-drag-id="${e(id)}" tabindex="0" aria-label="${e(label)} 순서 변경: 스페이스 키"><span class="v3-grip" aria-hidden="true"><svg width="24" height="24" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><path d="M4 9h16M4 15h16"/></svg></span>${html}</div>`;}
  function playlistView(list){
    const items=list.items.filter(i=>!i.hiddenBy);
    return `<div class="v3-list-tools"><span>${items.length}곡</span>${button('곡 추가','add-source',`data-list="${e(list.id)}"`,'command primary')}<button type="button" class="v3-more" data-ui="list-menu" data-list="${e(list.id)}" aria-label="플레이리스트 메뉴">⋮</button></div>`+
      `<div class="pl-detail-selection-space" aria-hidden="true"></div><div class="v3-sortable" data-sort-list="${e(list.id)}">`+items.map(item=>{
        const own=F.songs.get(item.songId),c=item.candidate||F.catalog.get('TJ:'+item.key.slice(3));
        const route=own?.active?`data-to="${e(F.songRoute(own.id))}"`:`data-v3="list-item" data-list="${e(list.id)}" data-candidate="${e(c.brand+':'+c.number)}"`;
        return dragRow('song',item.id,titleOf(item),`<button type="button" class="v3-list-song" ${route}>${own?.active?`<span class="tier">${e(own.tier)}</span>`:""}<span class="compact-copy"><strong>${e(own?.active?own.title:c.title)}</strong><small>${e(own?.active?own.artist+' · '+own.version:c.artist+' · '+c.brand+' '+c.number)}</small></span>${own?.active?`<span class="key">${e(own.key)}</span>`:icon('chevron',16)}</button>`);
      }).join('')+`</div><p class="v3-sort-status" role="status"></p>`+(!items.length?note('아직 담은 곡이 없어요. 내 곡에 없는 곡도 검색이나 차트에서 담을 수 있어요.'):'');
  }
  function playlistsView(){
    const lists=[...F.playlists.values()],count=lists.reduce((n,p)=>n+p.items.filter(i=>!i.hiddenBy).length,0);
    return `<div class="v4-playlist-summary"><span>나만의 선곡</span><small>${lists.length}개 목록 · ${count}곡</small></div><div class="v3-sortable v4-playlist-library" data-sort-list="all">`+lists.map((p,index)=>{
      const items=p.items.filter(i=>!i.hiddenBy),titles=items.slice(0,2).map(titleOf).join(' · ');
      return dragRow('list',p.id,p.title,`<button type="button" class="v3-list-song v4-playlist-card" data-to="${e(p.id)}"><span class="v4-playlist-cover" aria-hidden="true">${playlistGlyph(p.icon)}</span><span class="compact-copy"><strong>${e(p.title)}</strong><small>${e(titles||'첫 곡을 담아보세요')}</small></span><span class="v4-playlist-count">${items.length}<small>곡</small></span>${icon('chevron',14)}</button>`);
    }).join('')+`</div><p class="v3-sort-status" role="status"></p><button type="button" class="command primary v4-playlist-create" data-to="playlist-create">${icon('plus',17)} 새 플레이리스트</button>`+note('목록을 길게 눌러 선택하세요. 순서 변경 버튼을 누르면 손잡이로 옮길 수 있어요.');
  }
  function recordCard(r){
    const t=String(r.at).padStart(12,'0'),date=`${Number(t.slice(4,6))}월 ${Number(t.slice(6,8))}일 ${Number(t.slice(8,10))<12?'오전':'오후'} ${Number(t.slice(8,10))%12||12}:${t.slice(10,12)}`;
    const available=r.local||r.cloud==='보관됨';
    return `<article class="v3-record-card"><button type="button" class="v3-record-copy" data-v3="record-open" data-record="${e(r.id)}"><time>${e(date)}${!r.songId?" · 곡 미연결":""}</time><span class="v3-record-song"><span class="tier" data-tier="${e(r.tier)}">${e(r.tier)}</span><span class="compact-copy"><strong>${e(r.title)}</strong><small>${e(r.artist)}</small></span><span class="key ${r.key.startsWith('여')?'female':r.key.startsWith('남')?'male':''}">${e(r.key)}</span></span></button><div class="v3-record-action">${button('▶ '+F.renderHelpers.duration(r.duration),'record-play',`data-record="${e(r.id)}" aria-label="${e(r.title)} 재생 ${F.renderHelpers.duration(r.duration)}" ${available?'':'disabled'}`,'v3-duration')}<small>${e(!available?'재생할 파일 없음':'')}</small></div></article>`;
  }
  R.recordCard=recordCard;
  const time=value=>F.renderHelpers.duration(Math.floor(value))+'.'+Math.floor((value%1)*10);
  function playback(){
    const r=F.recordings.get(s.record)||F.recordings.get('r2'),available=r.local||r.cloud==='보관됨';
    const bars=Array.from({length:Math.ceil(r.duration/Math.min(r.duration,30)*100)},(_,i)=>`<i style="height:${10+Math.round(Math.abs(Math.sin(i*1.7)*Math.cos(i*.23))*70)}%"></i>`).join('');
    return `<div class="v3-player"><div class="v3-player-time" data-v3-time>${time(s.position)}</div><p class="v3-player-total">${time(r.duration)}</p><div class="v3-wave" data-wave-seek tabindex="0" role="slider" aria-label="재생 위치" aria-valuemin="0" aria-valuemax="${r.duration}" aria-valuenow="${s.position}"><div class="v3-wave-track" style="width:${r.duration/Math.min(r.duration,30)*100}%;transform:translateX(${-s.position/r.duration*100}%)">${bars}</div><span class="v3-playhead"></span></div><div class="v3-play-controls">${button('↶ 5','skip','data-seconds="-5" aria-label="5초 뒤로"','v3-skip')}${button(s.playing?'Ⅱ':'▶','play',`aria-label="${s.playing?'일시 정지':'재생'}" ${available?'':'disabled'}`,'v3-play-main')}${button('5 ↷','skip','data-seconds="5" aria-label="5초 앞으로"','v3-skip')}</div><p class="v3-player-state">${e(X.fileState(r))}</p></div>`;
  }
  function backupSummary(example='review',done=false){
    return `<div class="v3-import-summary">${field(done?'가져온 기록':'가져올 기록','내 곡 3개 · 녹음 정보 8개 · 녹음 파일 7개')}`+
      `<details open><summary>이미 있는 기록 · 2개</summary><p>같은 기록은 한 번만 남겨요. 이미 있는 녹음 파일도 다시 저장하지 않아요.</p></details>`+
      (example==='review'?`<details open><summary>이번에 가져오지 않는 항목 · 2개</summary><p><strong>금영 번호로 담아 둔 곡 1개</strong><br>TJ에서 같은 곡을 다시 찾아 플레이리스트에 담아 주세요.</p><p><strong>영구 삭제한 기록 1개</strong><br>삭제한 기록은 백업에 있어도 되살리지 않아요.</p></details>`:'')+`</div>`;
  }
  function backupImport(){return note('백업 파일을 선택하면 내용을 확인해요. 가져오기를 누르면 파일 검사 후 복원해요.')+
    (s.backup?field('선택한 파일',s.backup.name):`<div class="v3-file-empty">${icon('file',32)}<strong>백업 파일을 선택해 주세요</strong><small>노래기록에서 내보낸 ZIP 파일</small></div>`)+button(s.backup?'파일 다시 선택':'파일 선택','backup-select')+
    button('가져오기','import-start',s.backup?'':'disabled','command primary')+note('기존 기록은 유지해요. 이미 있는 기록은 중복으로 만들지 않아요.');}
  function extra(screen){
    const id=screen.id,c=candidateFor(screen);
    if(id==='v5-list-icon'){const list=F.playlists.get(s.iconList);return `<form class="x-form">${iconPicker(list?.icon)}</form>`+button('저장','save-list-icon','','command primary')+button('취소','back');}
    if(c)return candidateView(c);
    if(id==='playlists')return playlistsView();
    const list=F.playlists.get(F.listScreens.get(id));if(list)return playlistView(list);
    if(id==='v3-add-source')return note('내 곡 등록 없이도 플레이리스트에 먼저 담을 수 있어요.')+
      selection('내 곡에서 선택','등록해 둔 곡을 여러 개 선택','own-picker','','music').replace('data-v3="own-picker"','data-ui="list-picker"')+
      selection('인기 차트','인기곡을 찾아 이 목록에 담기','catalog-chart','','chart')+
      selection('검색','곡명·가수·번호로 새 곡 찾기','catalog-search','','search')+selection('직접 등록','곡명과 가수를 직접 입력해 담기','record-manual','','edit');
    if(id==='v3-record-source')return note('어디에서 곡을 고를까요?')+
      selection('내 곡','등록해 둔 곡에서 선택','record-own')+
      selection('플레이리스트','목록에 담아 둔 곡에서 선택','record-lists','','list')+
      selection('검색','노래방 곡명·가수·번호로 찾기','record-search','','search')+
      selection('직접 등록','검색에 없는 곡을 직접 입력','record-manual','','edit');
    if(id==='v3-record-lists')return [...F.playlists.values()].map(p=>selection(p.title,p.items.filter(i=>!i.hiddenBy).length+'곡','record-list',`data-list="${e(p.id)}"`,'list')).join('')||note('아직 플레이리스트가 없어요.');
    if(id==='v3-record-list'){
      const list=F.playlists.get(s.recordList);return note(list?.title||'플레이리스트')+(list?.items.filter(i=>!i.hiddenBy).map(item=>{
        const own=F.songs.get(item.songId),c=item.candidate||F.catalog.get('TJ:'+item.key.slice(3));
        return selection(titleOf(item),own?.active?'내 곡에 있음 · 바로 연결':'내 곡 등록 후 녹음 연결','record-pick',own?.active?`data-song="${e(own.id)}"`:`data-candidate="${e(c.brand+':'+c.number)}"`);
      }).join('')||note('이 목록은 비어 있어요.'));
    }
    if(id==='v2-playback')return playback();
    if(id==='backup')return selection('백업 내보내기','내 기록과 녹음 파일을 ZIP으로 저장','route','data-route="backup-export"','file')+selection('백업 가져오기','백업 파일에서 기록 복원','route','data-route="backup-import"','file');
    if(id==='backup-import')return backupImport();
    if(id==='v3-backup-file')return selection('노래기록_2026-10-19.zip','기록과 녹음 파일','backup-file','data-example="normal"','file')+selection('노래기록_이전_백업.zip','일부 항목을 확인해야 하는 백업','backup-file','data-example="review"','file')+selection('노래기록_손상된_백업.zip','열 수 없는 파일','backup-file','data-example="damaged"','file')+button('취소','back');
    if(id==='v3-import-progress')return `<div class="v3-file-empty" role="status"><span class="v3-spinner"></span><strong>${s.importStage==='checking'?'백업 파일을 확인하고 있어요':'기록을 가져오고 있어요'}</strong><small>기존 기록과 파일을 안전하게 확인해요.</small></div>`+button('취소','import-cancel');
    if(id==='import-preview')return backupSummary('review')+button('가져오기','import-preview-start','','command primary')+button('취소','back');
    if(id==='import-done')return `<div class="v3-song-heading"><span class="v3-eyebrow">백업 가져오기</span><h3>${s.backup?.example==='normal'?'가져왔어요':'일부 항목을 제외하고 가져왔어요'}</h3></div>`+backupSummary(s.backup?.example||'review',true)+button('완료','route','data-route="backup"','command primary');
    if(id==='import-error')return `<div class="v3-song-heading"><h3>백업 파일을 열 수 없어요</h3><p>파일이 손상되었거나 지원하지 않는 형식이에요. 기존 기록은 변경하지 않았어요.</p></div>`+button('다른 파일 선택','backup-select','','command primary');
    return null;
  }
  if(!F.screenMap.has('import-error'))addScreen('import-error','가져오기 실패','songs','backup-import');
  const basePhone=R.phone;
  R.phone=function(screen,interactive=true){
    const template=document.createElement('template');template.innerHTML=basePhone(screen,interactive);
    const phone=template.content.querySelector('.phone');if(!phone)return template.innerHTML;
    const body=phone.querySelector('.phone-body'),heading=phone.querySelector('.phone-header h2'),custom=extra(screen);
    if(custom!==null)body.innerHTML=custom;
    const songDelete=body.querySelector('[data-flow="delete-song"]');
    if(songDelete){
      for(const label of body.querySelectorAll('.field small'))if(label.textContent.trim()==='아쉬운 점')label.textContent='메모';
      const title=body.querySelector('.empty-state');
      if(title){
        const actions=document.createElement('div');actions.className='v3-song-top-actions';title.after(actions);
        actions.innerHTML='<button type="button" class="v3-more" data-v3="song-menu" aria-label="곡 메뉴" aria-haspopup="menu" aria-expanded="false">⋮</button><div class="v3-song-menu" role="menu" hidden></div>';
        const menu=actions.querySelector('[role="menu"]'),playlist=body.querySelector('[data-flow="song-playlists"]');
        songDelete.setAttribute('role','menuitem');menu.append(songDelete);
        if(playlist){playlist.setAttribute('role','menuitem');menu.append(playlist);}
      }
    }
    if(F.listScreens.has(screen.id)||screen.id.startsWith('v3-'))phone.querySelector('.phone-header p')?.remove();
    if(['charts','charts-ky'].includes(screen.id)){
      phone.querySelector('.v2-chart-heading small')?.remove();phone.querySelector('.v2-chart-info')?.remove();
    }
    for(const target of phone.querySelectorAll('[data-flow="candidate"]')){
      const c=F.catalog.get(target.dataset.candidate);if(!c)continue;
      delete target.dataset.flow;target.dataset.v3='candidate';
      const copy=target.querySelector('.review-result-copy');
      if(screen.tab==='search')copy?.querySelector('.v3-membership')?.remove();
      else if(!['charts','charts-ky'].includes(screen.id)&&copy&&!copy.querySelector('.v3-membership'))copy.insertAdjacentHTML('beforeend',membershipBadge(c));
    }
    for(const target of phone.querySelectorAll('[data-flow="discover"]')){
      const list=F.listScreens.get(screen.id);if(list){delete target.dataset.flow;target.dataset.v3='add-source';target.dataset.list=list;}
    }
    for(const target of phone.querySelectorAll('[data-flow="record-song-picker"]')){delete target.dataset.flow;target.dataset.v3='record-source';}
    for(const row of phone.querySelectorAll('.flow-record-row')){
      if(row.dataset.flow==='representative')continue;
      const record=F.recordings.get(F.recordScreens.get(row.dataset.to));if(record)row.outerHTML=recordCard(record);
    }
    phone.querySelectorAll('.flow-storage-help summary').forEach(n=>n.textContent='서버 자동 보관 기준');
    if(screen.id==='live-register'&&F.registration){
      const confirm=body.querySelector('[data-flow="register-confirm"]');
      if(confirm){confirm.textContent=F.ui.context?.draft?'등록하고 녹음 연결':'내 곡 등록';confirm.insertAdjacentHTML('beforebegin',R.block({type:'editField',source:'live-register',scope:'registration',kind:'tier',title:'곡 티어',value:F.registration.values.tier}));}
      body.insertAdjacentHTML('beforeend',`<label class="registration-note">메모<textarea data-registration-note maxlength="2000">${e(F.registration.values.note||'')}</textarea></label>`);
    }
    if(screen.id==='v2-list-menu'){
      body.querySelector('[data-to="v2-list-order"]')?.remove();
      const group=body.querySelector('.v2-settings-group');
      if(group){const item=document.createElement('template');item.innerHTML=R.block({type:'row',title:'아이콘 수정',sub:'플레이리스트 아이콘 선택',to:'v5-list-icon',icon:'edit'});const action=item.content.querySelector('button');action.removeAttribute('data-to');action.dataset.v3='edit-list-icon';group.prepend(item.content);}
    }
    if(screen.id==='playlist-create'){const form=body.querySelector('form');if(form)form.insertAdjacentHTML('beforeend',iconPicker('music'));}
    if(screen.id==='v2-playback'){
      const r=F.recordings.get(s.record)||F.recordings.get('r2');heading.textContent=r.artist+' · '+r.title+' '+r.key;heading.classList.add('v3-player-title');
      const settings=phone.querySelector('.settings-button');if(settings)settings.outerHTML=button('⋮','record-details','aria-label="녹음 상세 메뉴"','v3-more');
      else heading.insertAdjacentHTML('afterend',button('⋮','record-details','aria-label="녹음 상세 메뉴"','v3-more'));
      phone.classList.add('v3-player-phone');
    }
    if(['v2-draft-tags','x-record-edit','record-filter'].includes(screen.id)){
      const form=body.querySelector('form');
      if(form){
        const manage=kind=>`<button type="button" class="v3-manage-link" data-to="v2-class" data-class-manage="${kind}">${icon('edit',14)}<span>${kind} 수정</span></button>`;
        for(const [name,kind] of [['condition','컨디션'],['tag','태그']]){
          const select=form.querySelector(`select[name="${name}"]`);if(!select)continue;
          const label=select.parentElement,group=document.createElement('div');group.className='v3-class-select';
          group.innerHTML=`<div class="v3-class-heading"><span>${kind}</span>${manage(kind)}</div>`;
          label.replaceWith(group);select.setAttribute('aria-label',kind);group.append(select);
        }
        const legend=form.querySelector('fieldset legend');if(legend){
          const heading=document.createElement('div');heading.className='v3-class-heading';heading.innerHTML=`<span>태그</span>${manage('태그')}`;
          legend.parentElement.before(heading);legend.classList.add('v3-sr-only');
        }
        form.querySelectorAll('p').forEach(p=>{if(p.textContent.includes('샘플 시간대'))p.remove();});
        restoreForm(form,screen.id);
      }
    }
    if(screen.id==='v2-class'&&s.classOrigin)body.insertAdjacentHTML('beforeend',button('선택 화면으로 돌아가기','class-return','','command primary'));
    const topActions=[];
    if(screen.id==='songs'){
      const add=body.querySelector('[data-flow="discover"]');
      if(add){add.innerHTML=icon('plus',17)+'<span>내 곡 등록</span>';topActions.push(add);}
    }
    if(screen.id==='playlists'){const add=body.querySelector('[data-to="playlist-create"]');if(add)topActions.push(add);}
    if(screen.id==='live-register'){const confirm=body.querySelector('[data-flow="register-confirm"]');if(confirm)topActions.push(confirm);}
    if(['playlist-create','v2-manual'].includes(screen.id)){
      const actions=body.querySelector('.v2-form-actions');if(actions)topActions.push(actions);
    }
    if(topActions.length){
      const actions=document.createElement('div');actions.className='v4-top-actions';actions.setAttribute('aria-label','등록 작업');
      for(const action of topActions)actions.append(action);
      body.prepend(actions);
    }
    if(screen.id==='v3-record-list'&&s.recordList)heading.textContent=F.playlists.get(s.recordList)?.title||'곡 선택';
    if(screen.id==='v2-class')phone.classList.add('v3-class-phone');
    if(screen.id==='live-candidate')phone.classList.add('v3-candidate-phone');
    if(s.chooseLists){phone.insertAdjacentHTML('beforeend',`<div class="control-overlay"><button class="control-scrim" data-v3="close-choice" aria-label="닫기"></button><section class="control-sheet" role="dialog" aria-modal="true" aria-label="플레이리스트에 추가"><h3>플레이리스트에 추가</h3>${[...F.playlists.values()].map(list=>{const exists=list.items.some(i=>i.key===keyFor(s.chooseLists)&&!i.hiddenBy);return button(list.title+(exists?' · 추가됨':''),'choose-list',`data-list="${e(list.id)}" ${exists?'disabled':''}`,'control-option');}).join('')}${button('취소','close-choice')}</section></div>`);}
    if(s.restoreCandidate){phone.insertAdjacentHTML('beforeend',`<div class="control-overlay"><button class="control-scrim" data-v3="restore-cancel" aria-label="취소"></button><section class="control-sheet" role="dialog" aria-modal="true" aria-label="내 곡 복원"><h3>휴지통의 곡을 복원할까요?</h3><p class="control-caption">${e(s.restoreCandidate.title)}<br>기존 내 곡과 연결 기록을 복원해요. 지금 플리에 담긴 곡은 중복으로 추가하지 않아요.</p>${button('복원하고 내 곡 보기','restore-own','','command primary')}${button('취소','restore-cancel')}</section></div>`);}
    for(const badge of phone.querySelectorAll('.tier'))badge.dataset.tier=badge.textContent.trim();
    for(const badge of phone.querySelectorAll('.key')){
      badge.textContent=badge.textContent.replace(/^([남여])\s+[+-]?0$/,'$1');
      badge.classList.toggle('male',badge.textContent.trim().startsWith('남'));
      badge.classList.toggle('female',badge.textContent.trim().startsWith('여'));
    }
    phone.classList.toggle('v4-light',s.light);
    const settings=phone.querySelector('.phone-header .settings-button');
    if(settings){const toggle=document.createElement('button');toggle.type='button';toggle.className='icon-button v4-theme-toggle';toggle.dataset.v3='theme-toggle';toggle.setAttribute('aria-label',s.light?'다크 모드 켜기':'다크 모드 끄기');toggle.setAttribute('aria-pressed',String(!s.light));toggle.innerHTML='<svg width="21" height="21" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.7" aria-hidden="true"><path d="M20.5 13.2A8.7 8.7 0 0 1 10.8 3.5a8.8 8.8 0 1 0 9.7 9.7Z"/></svg>';settings.before(toggle);}
    return template.innerHTML;
  };
  function snapshotForm(){const form=document.querySelector('.device-holder .x-form');if(form)s.forms.set(current(),[...new FormData(form).entries()]);}
  function restoreForm(form,id){const values=s.forms.get(id);if(!values)return;
    const tags=form.querySelector('fieldset');if(tags)for(const [,value]of values.filter(([key])=>key==='tags'))if(![...tags.querySelectorAll('input')].some(n=>n.value===value))tags.insertAdjacentHTML('beforeend',`<label><input type="checkbox" name="tags" value="${e(value)}" checked>${e(value)} (기존 기록)</label>`);
    for(const input of form.querySelectorAll('[name]')){
      const chosen=values.filter(([key])=>key===input.name).map(([,value])=>value);
      if(input.type==='checkbox'){input.toggleAttribute('checked',chosen.includes(input.value));continue;}
      if(!chosen.length)continue;
      if(input.tagName==='SELECT'&&![...input.options].some(o=>o.value===chosen[0]))input.add(new Option(chosen[0],chosen[0]));
      if(input.tagName==='SELECT')for(const option of input.options)option.toggleAttribute('selected',option.value===chosen[0]);
      else if(input.tagName==='TEXTAREA')input.textContent=chosen[0];else input.setAttribute('value',chosen[0]);
    }
  }
  function openRecord(id,playing=false){s.record=id;s.position=0;s.playing=playing;go('v2-playback');}
  function startImport(){
    if(!s.backup)return;s.importStage='checking';go('v3-import-progress');
    clearTimeout(s.importTimer);s.importTimer=setTimeout(()=>{
      if(current()!=='v3-import-progress')return;
      if(s.backup.example==='damaged'){s.importStage='idle';go('import-error');return;}
      s.importStage='restoring';render();s.importTimer=setTimeout(()=>{if(current()==='v3-import-progress'){s.importStage='done';go('import-done');}},400);
    },650);
  }
  function prepareRecordSelection(){F.ensureDraft(F.screenMap.get(current()));F.draft.source=current();F.ui.context={draft:current(),source:current()};F.ui.pickQuery='';F.popup={kind:'record-source'};render();}
  // Window capture intentionally precedes the legacy document handlers.
  let pressedButton=null,ignoreNativeClick=null;
  window.addEventListener('dragstart',event=>{if(event.target.closest('.phone button'))event.preventDefault();},true);
  window.addEventListener('pointerdown',event=>{const b=event.target.closest('.device-holder button');pressedButton=b&&!b.disabled&&!b.closest('.v3-draggable')&&event.button===0?{b,x:event.clientX,y:event.clientY,id:event.pointerId}:null;},true);
  window.addEventListener('pointercancel',()=>{pressedButton=null;},true);
  window.addEventListener('pointerup',event=>{const press=pressedButton;pressedButton=null;if(!press||press.id!==event.pointerId||!press.b.isConnected||Math.hypot(event.clientX-press.x,event.clientY-press.y)<4)return;const target=document.elementFromPoint(event.clientX,event.clientY);if(target?.closest('button')!==press.b)return;ignoreNativeClick={button:press.b,until:performance.now()+500};press.b.click();},true);
  window.addEventListener('click',event=>{if(event.isTrusted&&ignoreNativeClick&&performance.now()<ignoreNativeClick.until&&event.target.closest('button')===ignoreNativeClick.button){event.preventDefault();event.stopImmediatePropagation();ignoreNativeClick=null;}},true);
  window.addEventListener('click',event=>{
    if(window.PLAYLIST_EDIT?.active()&&event.target.closest('.device-holder .v3-draggable'))return;
    if(!event.target.closest('.v3-song-top-actions'))for(const menu of document.querySelectorAll('.v3-song-menu:not([hidden])')){menu.hidden=true;menu.parentElement.querySelector('[data-v3="song-menu"]').setAttribute('aria-expanded','false');}
    const b=event.target.closest('button');if(!b||b.disabled)return;const d=b.dataset;
    if(s.suppressClick&&b.closest('.v3-draggable')){event.preventDefault();event.stopImmediatePropagation();s.suppressClick=false;return;}
    if(d.classManage){snapshotForm();s.classOrigin=current();}
    if(d.ui==='list-menu')s.iconList=d.list;
    if(d.ui==='class-edit')s.classRename=b.closest('.v2-class-row')?.querySelector('span')?.textContent;
    if(d.ui==='class-save'&&s.classRename){const name=document.querySelector('.device-holder input[name="className"]')?.value.trim(),previous=s.classRename;queueMicrotask(()=>{if(name&&current()==='v2-class')for(const [id,values]of s.forms)s.forms.set(id,values.map(([k,v])=>[k,(k==='condition'||k==='tags'||k==='tag')&&v===previous?name:v]));});}
    if((d.x==='record-save'||d.x==='cancel'||d.x==='filter-apply'||d.x==='filter-reset'||d.ui==='draft-tags-save'||d.ui==='back')&&['x-record-edit','record-filter','v2-draft-tags'].includes(current()))s.forms.delete(current());
    if(d.to==='v2-class'&&!d.classManage)s.classOrigin=null;
    if(d.jump||b.classList.contains('tab'))F.ui.context=null;
    if(d.to&&F.listScreens.has(d.to)&&d.v3===undefined)F.ui.context={playlist:F.listScreens.get(d.to),source:d.to,mode:'item'};
    if(d.ui==='play-open'){event.preventDefault();event.stopImmediatePropagation();openRecord(d.record);return;}
    if(d.ui==='manual-save'&&F.ui.context?.draft){
      event.preventDefault();event.stopImmediatePropagation();const values=new FormData(document.querySelector('.device-holder .x-form')),title=String(values.get('title')||'').trim(),artist=String(values.get('artist')||'').trim();
      if(!title||!artist){document.querySelector('.v2-action-error').textContent='곡명과 가수를 입력해 주세요.';return;}
      const id='manual:feedback-'+Date.now();F.songs.set(id,{id,number:null,title,artist,suitable:values.has('suitable'),version:F.manualRegistration.version,key:F.manualRegistration.key,tier:F.manualRegistration.tier,added:Date.now(),active:true,representative:null,note:String(values.get('note')||'')});F.manualRegistration=F.freshManualRegistration();F.selectSong(id);window.Prototype.returnTo(F.ui.context.draft);return;
    }
    if(!d.v3)return;event.preventDefault();event.stopImmediatePropagation();
    switch(d.v3){
      case 'pick-icon':{const picker=b.closest('.v5-icon-picker');picker.querySelector('input[name="playlistIcon"]').value=d.icon;for(const option of picker.querySelectorAll('[data-icon]'))option.setAttribute('aria-pressed',String(option.dataset.icon===d.icon));break;}
      case 'edit-list-icon':s.iconList=s.iconList||F.ui.context?.playlist;go('v5-list-icon');break;
      case 'save-list-icon':{const list=F.playlists.get(s.iconList);if(list){list.icon=document.querySelector('.device-holder input[name="playlistIcon"]')?.value||'music';window.Prototype.returnTo(list.id);}break;}
      case 'theme-toggle':snapshotForm();s.light=!s.light;localStorage.setItem('song-record-preview-light',String(s.light));render();break;
      case 'song-menu':{const menu=b.parentElement.querySelector('[role="menu"]');menu.hidden=!menu.hidden;b.setAttribute('aria-expanded',String(!menu.hidden));break;}
      case 'back':back();break;
      case 'route':go(d.route);break;
      case 'candidate':F.ui.candidate=d.candidate;go('live-candidate');break;
      case 'register':register(F.catalog.get(d.candidate));break;
      case 'candidate-lists':s.chooseLists=F.catalog.get(d.candidate);render();break;
      case 'close-choice':s.chooseLists=null;render();break;
      case 'choose-list':addCandidate(d.list,s.chooseLists);s.chooseLists=null;go(d.list);break;
      case 'restore-cancel':s.restoreCandidate=null;render();break;
      case 'restore-own':{const c=s.restoreCandidate,own=F.songs.get(keyFor(c));if(own&&X.restore(own.trashBatch)){for(const list of F.playlists.values())for(const item of list.items)if(!item.hiddenBy&&item.key===own.id){item.songId=own.id;delete item.candidate;}s.restoreCandidate=null;register(c);}break;}
      case 'candidate-add':{const list=F.ui.context?.playlist,c=F.catalog.get(d.candidate);if(list&&c){addCandidate(list,c);F.ui.context={playlist:list,source:list,mode:'item'};window.Prototype.returnTo(list);}break;}
      case 'list-item':F.ui.context={playlist:d.list,source:d.list,mode:'item'};F.ui.candidate=d.candidate;go('live-candidate');break;
      case 'add-source':F.ui.context={playlist:d.list,source:d.list,mode:'add'};F.popup={kind:'discover'};render();break;
      case 'catalog-chart':go('charts');break;
      case 'catalog-search':F.ui.brand='TJ';F.ui.catalogQuery='';go('search');break;
      case 'record-source':prepareRecordSelection();break;
      case 'record-own':F.close();go('live-pick-record');break;
      case 'record-lists':F.close();go('v3-record-lists');break;
      case 'record-list':s.recordList=d.list;go('v3-record-list');break;
      case 'record-search':F.close();F.ui.catalogQuery='';F.ui.brand='TJ';go('search');break;
      case 'record-manual':F.close();go('v2-manual');break;
      case 'record-pick':if(d.song){F.selectSong(d.song);window.Prototype.returnTo(F.ui.context?.draft||'draft');}else register(F.catalog.get(d.candidate));break;
      case 'record-open':openRecord(d.record);break;
      case 'record-play':openRecord(d.record,true);break;
      case 'record-details':s.playing=false;go(F.recordRoute(s.record));break;
      case 'play':{const r=F.recordings.get(s.record);if(r&&(r.local||r.cloud==='보관됨')){if(s.position>=r.duration)s.position=0;s.playing=!s.playing;render();}break;}
      case 'skip':s.position=Math.max(0,Math.min(F.recordings.get(s.record)?.duration||0,s.position+Number(d.seconds)));render();break;
      case 'class-return':window.Prototype.returnTo(s.classOrigin||'draft');break;
      case 'backup-select':go('v3-backup-file');break;
      case 'backup-file':s.backup={example:d.example,name:d.example==='normal'?'노래기록_2026-10-19.zip':d.example==='review'?'노래기록_이전_백업.zip':'노래기록_손상된_백업.zip'};go('backup-import');break;
      case 'import-start':startImport();break;
      case 'import-preview-start':s.backup={example:'review',name:'노래기록_이전_백업.zip'};startImport();break;
      case 'import-cancel':clearTimeout(s.importTimer);s.importStage='idle';go('backup-import');break;
    }
  },true);
  window.addEventListener('input',event=>{if(event.target.hasAttribute('data-v3-seek')){s.position=Number(event.target.value);updatePlayer();}});
  let wavePointer = null, waveOriginX = 0, waveOriginPosition = 0;
  function seekWave(event) {
    const wave = document.querySelector('.device-holder [data-wave-seek]');
    const recording = F.recordings.get(s.record);
    if (!wave || !recording) return;
    const rect = wave.getBoundingClientRect();
    s.position = Math.max(0, Math.min(recording.duration, waveOriginPosition - (event.clientX - waveOriginX) / rect.width * Math.min(recording.duration, 30)));
    wave.setAttribute('aria-valuenow', s.position);
    updatePlayer();
  }
  window.addEventListener('pointerdown', event => {const wave=event.target.closest('[data-wave-seek]');if(!wave)return;wavePointer=event.pointerId;waveOriginX=event.clientX;waveOriginPosition=s.position;wave.setPointerCapture(event.pointerId);});
  window.addEventListener('pointermove', event => {if(wavePointer===event.pointerId)seekWave(event);});
  for(const name of ['pointerup','pointercancel'])window.addEventListener(name,event=>{if(event.pointerId===wavePointer)wavePointer=null;});
  window.addEventListener('keydown',event=>{if(!event.target.matches('[data-wave-seek]')||!['ArrowLeft','ArrowRight'].includes(event.key))return;event.preventDefault();const r=F.recordings.get(s.record);s.position=Math.max(0,Math.min(r.duration,s.position+(event.key==='ArrowLeft'?-5:5)));updatePlayer();});
  function updatePlayer(){const r=F.recordings.get(s.record);if(!r)return;const root=document.querySelector('.device-holder');const timeNode=root?.querySelector('[data-v3-time]');if(timeNode)timeNode.textContent=time(s.position);const slider=root?.querySelector('[data-v3-seek]');if(slider)slider.value=s.position;const track=root?.querySelector('.v3-wave-track');if(track)track.style.transform=`translateX(${-s.position/r.duration*100}%)`;const wave=root?.querySelector('[data-wave-seek]');if(wave)wave.setAttribute('aria-valuenow',s.position);}
  let lastPlayerFrame = null;
  function animatePlayer(now) {
    const delta = lastPlayerFrame === null ? 0 : Math.min((now-lastPlayerFrame)/1000,.1);
    lastPlayerFrame = now;
    if(current()!=='v2-playback') s.playing=false;
    if(s.playing && wavePointer===null && !document.hidden){
      const duration=F.recordings.get(s.record)?.duration||0;
      s.position=Math.min(duration,s.position+delta);updatePlayer();
      if(s.position>=duration){s.playing=false;render();}
    }
    requestAnimationFrame(animatePlayer);
  }
  requestAnimationFrame(animatePlayer);
  // Pointer drag is provisional until release; Escape/cancel restores the saved order.
  function beginDrag(row,pointer){s.drag.originalRows=[...s.drag.container.children];row.classList.add('v3-dragging');row.setAttribute('aria-grabbed','true');s.drag.active=true;s.drag.row=row;if(pointer!==null){row.setPointerCapture(pointer);const r=row.getBoundingClientRect(),ghost=row.cloneNode(true);ghost.classList.add('v3-drag-ghost');
 // The floating copy leaves the phone theme subtree: carry its resolved colors.
 const sources=[row,...row.querySelectorAll('*')],copies=[ghost,...ghost.querySelectorAll('*')];
 sources.forEach((source,i)=>{const style=getComputedStyle(source);for(const name of style)if(name.startsWith('--'))copies[i].style.setProperty(name,style.getPropertyValue(name));for(const name of ['color','background-color','border-top-color','border-right-color','border-bottom-color','border-left-color','fill','stroke'])copies[i].style.setProperty(name,style.getPropertyValue(name));});
 // One shared accent outline for both themes; source card borders must not override it.
 for(const edge of ['top','right','bottom','left'])ghost.style.removeProperty('border-'+edge+'-color');
 Object.assign(ghost.style,{position:'fixed',left:r.left+'px',top:r.top+'px',width:r.width+'px',height:r.height+'px',margin:'0',zIndex:'10000',pointerEvents:'none'});document.body.append(ghost);s.drag.ghost=ghost;s.drag.top=r.top;row.classList.add('v3-drag-placeholder');}const status=document.querySelector('.device-holder .v3-sort-status');if(status)status.textContent='위아래로 옮긴 뒤 놓으세요. Esc 키로 취소할 수 있어요.';}
  function finishDrag(save){const drag=s.drag;if(!drag)return;clearTimeout(drag.timer);drag.ghost?.remove();s.drag=null;if(!drag.active)return;
    if(save){const ids=[...drag.container.children].map(n=>n.dataset.dragId);if(drag.container.dataset.sortList==='all'){const lists=ids.map(id=>F.playlists.get(id));F.playlists.clear();lists.forEach(p=>F.playlists.set(p.id,p));}else{const list=F.playlists.get(drag.container.dataset.sortList),items=new Map(list.items.map(i=>[i.id,i]));list.items=[...ids.map(id=>items.get(id)),...list.items.filter(i=>i.hiddenBy)];}}
    s.suppressClick=drag.pointer!==null;setTimeout(()=>s.suppressClick=false,150);if(!save)drag.originalRows.forEach(row=>drag.container.append(row));drag.row.classList.remove('v3-dragging','v3-drag-placeholder');drag.row.setAttribute('aria-grabbed','false');const status=document.querySelector('.device-holder .v3-sort-status');if(status)status.textContent=save?'순서를 저장했어요.':'순서 변경을 취소했어요.';
  }
  window.addEventListener('pointerdown',event=>{
    const row=event.target.closest('.device-holder .v3-draggable');if(!row||event.button!==0||!window.PLAYLIST_EDIT?.ordering()||!event.target.closest('.v3-grip'))return;s.suppressClick=false;
    s.drag={row,container:row.parentElement,x:event.clientX,y:event.clientY,lastY:event.clientY,active:false,scrolling:false,pointer:event.pointerId};
    if(event.target.closest('.v3-grip')){beginDrag(row,event.pointerId);return;}
    s.drag.timer=setTimeout(()=>{if(s.drag&&!s.drag.scrolling)beginDrag(row,event.pointerId);},450);
  });
  window.addEventListener('pointermove',event=>{
    const drag=s.drag;if(!drag||drag.pointer!==event.pointerId)return;
    if(!drag.active){if(Math.hypot(event.clientX-drag.x,event.clientY-drag.y)>8){clearTimeout(drag.timer);drag.scrolling=true;const body=drag.row.closest('.phone-body');if(event.pointerType==='touch'){body.scrollTop+=drag.lastY-event.clientY;event.preventDefault();}drag.lastY=event.clientY;}return;}
    event.preventDefault();s.suppressClick=true;if(drag.ghost)drag.ghost.style.top=(drag.top+event.clientY-drag.y)+'px';const body=drag.row.closest('.phone-body'),rect=body.getBoundingClientRect();if(event.clientY<rect.top+40)body.scrollTop-=14;else if(event.clientY>rect.bottom-40)body.scrollTop+=14;
    const target=document.elementFromPoint(event.clientX,event.clientY)?.closest('.v3-draggable');if(target&&target!==drag.row&&target.parentElement===drag.container){const r=target.getBoundingClientRect(),before=new Map([...drag.container.children].map(n=>[n,n.getBoundingClientRect().top]));drag.container.insertBefore(drag.row,event.clientY<r.top+r.height/2?target:target.nextSibling);if(!matchMedia('(prefers-reduced-motion: reduce)').matches)for(const [n,top]of before){const dy=top-n.getBoundingClientRect().top;if(n!==drag.row&&dy)n.animate([{transform:`translateY(${dy}px)`},{transform:'translateY(0)'}],{duration:180,easing:'ease-out'});}}
  },{passive:false});
  window.addEventListener('pointerup',()=>{if(s.drag?.active)finishDrag(true);else if(s.drag){clearTimeout(s.drag.timer);s.suppressClick=s.drag.scrolling;s.drag=null;}});
  window.addEventListener('pointercancel',()=>finishDrag(false));
  window.addEventListener('keydown',event=>{
    if(event.key==='Escape'){const menu=document.querySelector('.device-holder .v3-song-menu:not([hidden])');if(menu){menu.hidden=true;const trigger=menu.parentElement.querySelector('[data-v3="song-menu"]');trigger.setAttribute('aria-expanded','false');trigger.focus();event.preventDefault();return;}}
    const row=event.target.closest('.device-holder .v3-draggable');
    if(event.key==='Escape'&&s.drag?.active){event.preventDefault();finishDrag(false);return;}
    if(!row||event.target!==row||!window.PLAYLIST_EDIT?.ordering())return;
    if([' ','Enter'].includes(event.key)){event.preventDefault();if(s.drag?.active)finishDrag(true);else{s.drag={row,container:row.parentElement,active:false,pointer:null};beginDrag(row,null);}return;}
    if(['ArrowUp','ArrowDown'].includes(event.key)&&s.drag?.active){event.preventDefault();const next=event.key==='ArrowUp'?row.previousElementSibling:row.nextElementSibling;if(next)row.parentElement.insertBefore(row,event.key==='ArrowUp'?next:next.nextSibling);row.focus();}
  });
  const previousAfter=window.EDIT_UI.afterRender;
  window.EDIT_UI.afterRender=function(...args){previousAfter(...args);const id=current();
    const tips={charts:['수집 시각과 기술 설명을 화면에서 없앴어요.','플리 추가 중에는 선택한 목록에 담는 동작만 보여요.','내 곡 등록 없이도 TJ 곡을 플리에 먼저 담을 수 있어요.'],playlists:['플리에만 담긴 곡을 나중에 내 곡으로 등록할 수 있어요.','곡과 목록을 길게 눌러 선택하세요. 순서 변경 버튼을 누르면 손잡이로 옮길 수 있어요.','키보드: 행에 초점 → 스페이스 → ↑/↓ → Enter, Esc 취소.'],recordings:['날짜 아래에 티어·곡명·가수·키를 한 줄로 배치했어요.','목록에서는 서버 보관 표시를 생략하고 재생 버튼에 선택한 강조색을 써요.','녹음을 누르면 재생 화면, 우측 ⋮에서 기존 상세로 이동해요.']};
    const section=id==='charts-ky'?'charts':F.listScreens.has(id)?'playlists':id;
    if(tips[section]){const node=document.querySelector('.review-changes');if(node)node.innerHTML=tips[section].map(t=>`<li>${e(t)}</li>`).join('');}
    if(id==='v2-playback'){const node=document.querySelector('.inspector .disclaimer');if(node)node.innerHTML='<strong>음원 없는 재생 시안</strong><br>실제 음원 파형은 베타 반영 때 연결해요. 현재 파형은 배치 확인용이에요. 버튼과 시간 이동만 시연해요.';}
    if(id==='v3-backup-file'){const node=document.querySelector('.inspector .disclaimer');if(node)node.innerHTML='<strong>샘플 백업 선택</strong><br>실제 파일을 읽거나 복원하지 않아요. 정상·일부 제외·손상 상태를 골라 화면 흐름을 확인해요.';}
  };
  render();
})();

/* Song suitability is independent of performance tier; prototype-only state. */
(() => {
  const F=window.FLOW,R=window.RENDER,P=window.Prototype;
  const heart='<svg width="19" height="19" viewBox="0 0 24 24" fill="currentColor" aria-hidden="true"><path d="M12 21 3.5 12.7C-2 7.2 5.5-.5 12 6c6.5-6.5 14 1.2 8.5 6.7Z"/></svg>';
  const choice=(scope,checked)=>`<label class="suitability-choice"><input type="checkbox" name="suitable" data-suitable="${scope}" ${checked?'checked':''}><span>${heart}<strong>나에게 어울리는 곡</strong><small>실력과 관계없이 내 음색·창법에 잘 맞는 곡</small></span></label>`;
  const sorted=F.sortedSongs;
  F.sortedSongs=function(){return sorted().filter(song=>!F.ui.suitableOnly||song.suitable);};
  const register=F.register;
  F.register=function(candidate,values){const song=register(candidate,values);song.suitable=Boolean(values?.suitable);song.note=String(values?.note||'');return song;};
  const commit=F.commitSong;
  F.commitSong=function(source){const tx=F.transaction,value=tx?.values.suitable,id=tx?.songId;const result=commit(source);if(id&&!F.transaction)F.songs.get(id).suitable=Boolean(value);return result;};
  // Two contrasting tiers demonstrate that suitability does not imply skill.
  F.songs.get('tj:04567').suitable=true;
  F.songs.get('tj:04569').suitable=true;
  const phone=R.phone;
  R.phone=function(screen,interactive=true){
    const t=document.createElement('template');t.innerHTML=phone(screen,interactive);
    const root=t.content.querySelector('.phone'),body=root?.querySelector('.phone-body');if(!body)return t.innerHTML;
    for(const meter of body.querySelectorAll('.v2-meter[role="meter"]')){
      const used=Number(meter.getAttribute('aria-valuenow')),max=Number(meter.getAttribute('aria-valuemax'));
      meter.style.setProperty('--usage-percent',`${max>0?Math.min(100,Math.max(0,used/max*100)):0}%`);
    }
    for(const row of body.querySelectorAll('.compact-row[data-to],.v3-list-song[data-to]')){
      const song=F.songFor(row.dataset.to);if(!song)continue;
      const mark=document.createElement('span');mark.className='song-suitability';
      if(song.suitable){mark.innerHTML=heart;mark.setAttribute('role','img');mark.setAttribute('aria-label','나에게 어울리는 곡');}else mark.setAttribute('aria-hidden','true');
      row.querySelector('.key')?.before(mark);
    }
    if(screen.id==='songs')body.querySelector('.options')?.insertAdjacentHTML('afterend',`<label class="suitability-filter"><input type="checkbox" data-suitable="filter" ${F.ui.suitableOnly?'checked':''}>${heart}<span>나에게 어울리는 곡만</span></label>`);
    if(screen.id==='live-register'&&F.registration)body.querySelector('[data-edit-open="version"]')?.insertAdjacentHTML('beforebegin',choice('registration',F.registration.values.suitable));
    if(screen.id==='v2-manual')body.querySelector('[data-edit-open="version"]')?.insertAdjacentHTML('beforebegin',choice('manual',F.manualRegistration.suitable));
    const song=F.songFor(screen.id);
    if(song){
      const editing=F.editorScreens.has(screen.id),html=choice(editing?'edit':'song',editing?F.transaction?.values.suitable:song.suitable);
      const meta=editing?null:body.querySelector('.song-meta');
      if(meta)meta.insertAdjacentHTML('afterend',html);else body.insertAdjacentHTML('beforeend',html);
    }
    return t.innerHTML;
  };
  document.addEventListener('change',event=>{
    const control=event.target,scope=control.dataset?.suitable;if(!scope)return;
    if(scope==='manual'){F.manualRegistration.suitable=control.checked;return;}
    if(scope==='filter')F.ui.suitableOnly=control.checked;
    if(scope==='registration')F.registration.values.suitable=control.checked;
    if(scope==='edit'&&F.transaction)F.transaction.values.suitable=control.checked;
    if(scope==='song')F.songFor(P.state.screen).suitable=control.checked;
    P.render();
  });
  P.render();
})();

// Supplemental screens are registered by this file after the base HTML model.
// Restore their deep link only once every renderer and screen has been installed.
(() => {
  const requested = new URLSearchParams(location.hash.slice(1)).get('screen');
  if (requested && window.FLOW?.screenMap.has(requested) &&
      window.Prototype?.state.screen !== requested) {
    window.Prototype.go(requested, true);
  }
})();

/* Registration drafts survive picker redraws. Candidate confirmation is centered. */
(() => {
  const F=window.FLOW,R=window.RENDER,phone=R.phone;
  document.addEventListener('input', event => {
    const control=event.target;
    if (control.matches('[data-registration-note]') && F.registration) F.registration.values.note=control.value;
    if (window.Prototype.state.screen==='v2-manual' && ['title','artist','note'].includes(control.name)) F.manualRegistration[control.name]=control.value;
  });
  R.phone=function(screen,interactive=true){
    const html=phone(screen,interactive);
    if(screen.id!=='live-candidate')return html;
    const parsed=document.createElement('template');parsed.innerHTML=html;
    const content=parsed.content.querySelector('.phone-body')?.innerHTML||'';
    const previous=F.nav.entries.at(-2)?.id;
    const background=F.screenMap.get(previous && previous!=='live-candidate'?previous:'search')||F.screenMap.get('search');
    return phone(background,false).replace('</article>',`<div class="control-overlay candidate-overlay"><button type="button" class="control-scrim" data-ui="back" aria-label="곡 선택 닫기"></button><section class="control-sheet" role="dialog" aria-modal="true" aria-label="곡 선택"><header class="control-sheet-header"><h3>곡 선택</h3><button type="button" class="control-close" data-ui="back">닫기</button></header>${content}</section></div></article>`);
  };
})();
window.Prototype.render();

/* One compact return-to-top control, shown only after scrolling charts. */
(() => {
  const R=window.RENDER,phone=R.phone;
  R.phone=function(screen,interactive=true){
    const html=phone(screen,interactive);
    return ['charts','charts-ky','songs','songs-groups','recordings','song-detail'].includes(screen.id) || /^live-song-/.test(screen.id) || /^(songs-sort-|review-group-sort-)/.test(screen.id)
      ? html.slice(0,html.lastIndexOf('</article>'))+'<button type="button" class="chart-to-top" data-chart-top aria-label="맨 위로" hidden>↑</button>'+html.slice(html.lastIndexOf('</article>')) : html;
  };
  document.addEventListener('scroll', event=>{
    if(!event.target.matches?.('.phone-body'))return;
    const button=event.target.closest('.phone')?.querySelector('[data-chart-top]');
    if(button)button.hidden=event.target.scrollTop<64;
  },true);
  document.addEventListener('click',event=>{
    if(event.target.closest('[data-chart-top]'))event.target.closest('.phone').querySelector('.phone-body').scrollTo({top:0,behavior:'smooth'});
  });
})();
window.Prototype.render();


/* Shared hold menu: actions never delete without a second confirmation. */
(function(){
 const F=window.FLOW,P=window.Prototype,e=window.RENDER.esc;
 let press=null,blockClick=false,bulk=null;
 const phone=()=>document.querySelector('.device-holder .phone');
 function close(){document.querySelector('.hold-overlay')?.remove();}
 function dialog(title,choices){
  close();const layer=document.createElement('div');layer.className='control-overlay hold-overlay';
  layer.innerHTML=`<section class="control-sheet" role="dialog" aria-modal="true" aria-label="${e(title)}"><h3>${e(title)}</h3><div class="hold-options"></div><button type="button" class="command secondary hold-cancel">취소</button></section>`;
  phone().append(layer);const options=layer.querySelector('.hold-options');
  choices.forEach(([label,action])=>{const b=document.createElement('button');b.type='button';b.className='command secondary';b.textContent=label;b.onclick=()=>{close();action();};options.append(b);});
  layer.querySelector('.hold-cancel').onclick=close;layer.addEventListener('click',()=>{blockClick=false;});layer.addEventListener('click',ev=>{if(ev.target===layer)close();});layer.querySelector('button')?.focus();
 }

 function order(listId){
  const all=listId==='all',list=F.playlists.get(listId);
  const values=all?[...F.playlists.values()]:list.items.filter(v=>!v.hiddenBy);
  const label=v=>all?v.title:(F.songs.get(v.songId)?.title||v.candidate?.title||'곡');
  function draw(){dialog(all?'플레이리스트 순서':'목록 순서 변경',[]);document.querySelector('.hold-overlay').classList.add('hold-order');const area=document.querySelector('.hold-options');
   values.forEach((v,i)=>{const row=document.createElement('div');row.className='hold-order-row';const text=document.createElement('span');text.textContent=(i+1)+'. '+label(v);row.append(text);
    for(const [symbol,d] of [['↑',-1],['↓',1]]){const b=document.createElement('button');b.textContent=symbol;b.type='button';b.setAttribute('aria-label',label(v)+(d<0?' 위로':' 아래로'));b.disabled=i+d<0||i+d>=values.length;b.onclick=()=>{[values[i],values[i+d]]=[values[i+d],values[i]];draw();};row.append(b);}area.append(row);
   });const save=document.createElement('button');save.type='button';save.className='command primary';save.textContent='순서 저장';save.onclick=()=>{if(all){F.playlists.clear();values.forEach(v=>F.playlists.set(v.id,v));}else list.items=[...values,...list.items.filter(v=>v.hiddenBy)];close();P.render();};area.append(save);
  }draw();
 }
 function menu(target){
  const drag=target.closest('.v3-draggable');
  if(drag){window.PLAYLIST_EDIT.select(drag);return;}
  const recordId=target.closest('[data-record]')?.dataset.record;
  if(recordId){const r=F.recordings.get(recordId);if(!r)return;dialog(r.title,[['녹음 삭제',()=>dialog('녹음을 휴지통으로 옮길까요?',[['녹음 삭제',()=>{r.active=false;const id='record-batch-'+Date.now();r.trashBatch=id;window.X.batches.set(id,{id,recordOnly:true,records:[{id:r.id}],items:[],deletedAt:Date.now()});P.render();}]])]]);return;}
  const route=target.closest('[data-to]')?.dataset.to,song=F.songFor(route);if(song?.active){bulk=new Set([song.id]);paintBulk();}
 }

 function visibleSongs(){return [...document.querySelectorAll('.device-holder .compact-row[data-to^="live-song-"]')].map(row=>({row,song:F.songFor(row.dataset.to)})).filter(v=>v.song?.active);}
 function paintBulk(){
  const root=phone();if(!root)return;
  if(P.state.screen!=='songs')bulk=null;
  root.querySelectorAll('.bulk-toolbar,.bulk-selection-row,.bulk-delete-bar,.bulk-check').forEach(n=>n.remove());
  root.classList.toggle('bulk-selecting',bulk!==null);if(bulk===null)return;
  const visible=visibleSongs();const all=visible.length>0&&visible.every(v=>bulk.has(v.song.id));
  const toolbar=document.createElement('div');toolbar.className='bulk-toolbar';
  toolbar.innerHTML=`<button type="button" class="bulk-all" role="checkbox" aria-checked="${all}" aria-label="전체 선택"><span class="bulk-box">${all?'✓':''}</span><span>전체</span></button><button type="button" class="bulk-cancel">취소</button>`;
  const filter=root.querySelector('.suitability-filter');filter.after(toolbar);
  const count=document.createElement('span');count.className='bulk-count';count.textContent=String(bulk.size);count.setAttribute('aria-label',`${bulk.size}곡 선택됨`);toolbar.querySelector('.bulk-all').append(count);
  toolbar.querySelector('.bulk-all').onclick=()=>{visible.forEach(v=>all?bulk.delete(v.song.id):bulk.add(v.song.id));paintBulk();};
  toolbar.querySelector('.bulk-cancel').onclick=()=>{bulk=null;paintBulk();};
  for(const {row,song} of visible){const check=document.createElement('span');check.className='bulk-check bulk-box';check.setAttribute('role','checkbox');check.setAttribute('aria-label',song.title+' 선택');check.setAttribute('aria-checked',String(bulk.has(song.id)));check.textContent=bulk.has(song.id)?'✓':'';row.prepend(check);}
  const bar=document.createElement('div');bar.className='bulk-delete-bar';
  const button=document.createElement('button');button.type='button';button.className='command primary';button.textContent=bulk.size?`선택한 ${bulk.size}곡 삭제`:'삭제';button.disabled=bulk.size===0;
  button.onclick=()=>{const ids=[...bulk];dialog(`${ids.length}곡을 삭제할까요?`,[['곡만 삭제 · 녹음 유지',()=>{ids.forEach(id=>F.deleteSong(id,true));bulk=null;P.render();}],['곡과 녹음 함께 삭제',()=>{ids.forEach(id=>F.deleteSong(id,false));bulk=null;P.render();}]]);};bar.append(button);root.append(bar);
 }
 const previousBulkRender=window.EDIT_UI.afterRender;
 window.EDIT_UI.afterRender=function(...args){previousBulkRender?.apply(this,args);paintBulk();};
 window.addEventListener('click',ev=>{if(!bulk||ev.target.closest('.hold-overlay'))return;const row=ev.target.closest('.device-holder .compact-row[data-to^="live-song-"]');if(!row)return;const song=F.songFor(row.dataset.to);if(!song?.active)return;ev.preventDefault();ev.stopImmediatePropagation();if(blockClick){blockClick=false;return;}bulk.has(song.id)?bulk.delete(song.id):bulk.add(song.id);paintBulk();},true);
 function eligible(target){return target.closest('.v3-draggable,.v3-record-copy,.compact-row[data-to^="live-song-"]');}
 window.addEventListener('pointerdown',ev=>{blockClick=false;const target=eligible(ev.target);if(target?.matches('.v3-draggable')&&window.PLAYLIST_EDIT?.ordering())return;if(bulk&&target?.matches('.compact-row'))return;if(!target||ev.button!==0||ev.target.closest('.hold-overlay'))return;ev.stopImmediatePropagation();press={target,x:ev.clientX,y:ev.clientY};press.timer=setTimeout(()=>{if(!press)return;blockClick=true;menu(target);press=null;},500);},true);
 window.addEventListener('pointermove',ev=>{if(press&&Math.hypot(ev.clientX-press.x,ev.clientY-press.y)>8){clearTimeout(press.timer);press=null;}},true);
 for(const type of ['pointerup','pointercancel'])window.addEventListener(type,()=>{if(press)clearTimeout(press.timer);press=null;},true);
 window.addEventListener('click',ev=>{if(blockClick&&!ev.target.closest('.hold-overlay')){ev.preventDefault();ev.stopImmediatePropagation();blockClick=false;}},true);
 window.addEventListener('keydown',ev=>{if(ev.key==='Escape'&&document.querySelector('.hold-overlay')){ev.preventDefault();ev.stopImmediatePropagation();close();return;}if(ev.key==='Escape'&&bulk){ev.preventDefault();ev.stopImmediatePropagation();bulk=null;paintBulk();return;}if(ev.key==='ContextMenu'||(ev.shiftKey&&ev.key==='F10')){const t=eligible(ev.target);if(t){ev.preventDefault();menu(t);}}},true);
})();

/* Playlist selection and explicit reorder modes share the same in-place list. */
(()=>{
 const P=window.Prototype,F=window.FLOW;let mode=null,scope=null,selected=new Set(),saved=null,route=null;
 const root=()=>document.querySelector('.device-holder .phone');
 const container=()=>root()?.querySelector('.v3-sortable');
 let unfold=false,orderScrolled=false;
 function reset(){unfold=mode==='order'&&!orderScrolled;mode=null;selected.clear();saved=null;scope=null;}
 function renderKeepingScroll(){const body=root()?.querySelector('.phone-body'),top=body?.scrollTop||0;P.render();const next=root()?.querySelector('.phone-body');if(next){next.scrollTop=top;next.dispatchEvent(new Event('scroll'));}if(unfold){unfold=false;if(!matchMedia('(prefers-reduced-motion: reduce)').matches)root().querySelectorAll('.phone-header,.v4-top-actions,.v3-list-tools').forEach(el=>{const h=el.getBoundingClientRect().height;el.animate([{maxHeight:'0px',minHeight:'0px',height:'0px',opacity:0,transform:'translateY(-24px)'},{maxHeight:h+'px',minHeight:h+'px',height:h+'px',opacity:1,transform:'translateY(0)'}],{duration:250,easing:'ease-out'});});}}
 function restore(){if(scope==='all'){F.playlists.clear();saved.forEach(v=>F.playlists.set(v.id,v));}else if(F.playlists.has(scope))F.playlists.get(scope).items=saved;}
 function enterOrder(){const r=root(),body=r?.querySelector('.phone-body'),scrolled=(body?.scrollTop||0)>12;orderScrolled=scrolled;r?.classList.toggle('pl-fold-instant',scrolled);scope=container().dataset.sortList;route=P.state.screen;saved=scope==='all'?[...F.playlists.values()]:[...F.playlists.get(scope).items];mode='order';draw();}
 window.PLAYLIST_EDIT={renderKeepingScroll,active:()=>mode!==null,ordering:()=>mode==='order',select(row){const body=root()?.querySelector('.phone-body'),top=body?.scrollTop||0;root()?.classList.add('pl-fold-instant');scope=row.parentElement.dataset.sortList;route=P.state.screen;mode='select';selected=new Set([row.dataset.dragId]);draw();if(body){body.scrollTop=top;requestAnimationFrame(()=>{if(mode==='select')body.scrollTop=top;});}}};
 function draw(){const r=root(),c=container();if(!r)return;const scrollBody=r.querySelector('.phone-body'),scrollTop=scrollBody.scrollTop;if(route&&route!==P.state.screen){if(mode==='order')restore();reset();}r.querySelectorAll('.pl-edit-tools,.pl-edit-footer,.pl-edit-check,.pl-edit-menu').forEach(n=>n.remove());r.querySelectorAll('.pl-selection-slot').forEach(n=>n.classList.remove('pl-selection-slot'));r.classList.toggle('pl-order-scrolled',mode==='order'&&orderScrolled);r.classList.toggle('pl-ordering',mode==='order');r.classList.toggle('pl-selecting',mode==='select');if(!c)return;
 const orderButton=document.createElement('button');orderButton.type='button';orderButton.className='pl-edit-menu pl-order-trigger command secondary';orderButton.textContent='↕ 순서 변경';orderButton.onclick=enterOrder;
 const create=r.querySelector('.v4-playlist-create');const actions=create?.parentElement||r.querySelector('.v3-list-tools');if(actions){actions.classList.add('pl-action-row');if(create)create.before(orderButton);else{const add=actions.querySelector('[data-v3="add-source"]');if(add)add.before(orderButton);else actions.append(orderButton);}}
 if(!mode)return;orderButton.hidden=mode==='order';
 const bar=document.createElement('div');bar.className='pl-edit-tools';const cancel=document.createElement('button');cancel.textContent='취소';cancel.onclick=()=>{if(mode==='order')restore();reset();renderKeepingScroll();};
 if(mode==='select'){const all=document.createElement('button');all.className='pl-all';const rows=[...c.children];const checked=rows.length>0&&rows.every(x=>selected.has(x.dataset.dragId));all.innerHTML=`<span class="bulk-box" aria-checked="${checked}">${checked?'✓':''}</span> 전체 <span class="bulk-count">${selected.size}</span>`;all.onclick=()=>{rows.forEach(x=>checked?selected.delete(x.dataset.dragId):selected.add(x.dataset.dragId));draw();};bar.append(all);
 rows.forEach(row=>{const check=document.createElement('span');check.className='pl-edit-check bulk-box';check.setAttribute('aria-checked',String(selected.has(row.dataset.dragId)));check.textContent=selected.has(row.dataset.dragId)?'✓':'';row.prepend(check);});
 const footer=document.createElement('div');footer.className='pl-edit-footer bulk-delete-bar';const del=document.createElement('button');del.className='command primary';del.textContent=scope==='all'?`선택한 ${selected.size}개 플리 삭제`:`선택한 ${selected.size}곡 목록에서 제거`;del.disabled=!selected.size;del.onclick=()=>{if(!window.confirm(scope==='all'?'선택한 플레이리스트를 삭제할까요? 내 곡과 녹음은 유지됩니다.':'선택한 곡을 이 목록에서만 제거할까요? 내 곡과 녹음은 유지됩니다.'))return;if(scope==='all')selected.forEach(id=>F.playlists.delete(id));else{const list=F.playlists.get(scope);list.items=list.items.filter(x=>!selected.has(x.id));}reset();renderKeepingScroll();};footer.append(del);r.append(footer);
 }else{bar.append(cancel);const done=document.createElement('button');done.textContent='완료';done.onclick=()=>{reset();renderKeepingScroll();};bar.append(done);}
 if(mode==='select')bar.append(cancel);if(mode==='select'||(mode==='order'&&scope==='all')){const summary=scope==='all'?r.querySelector('.v4-playlist-summary'):c.previousElementSibling;summary.classList.add('pl-selection-slot');summary.removeAttribute('aria-hidden');summary.append(bar);}else c.before(bar);scrollBody.scrollTop=scrollTop;
 }
 const prev=window.EDIT_UI.afterRender;window.EDIT_UI.afterRender=function(...args){prev?.apply(this,args);draw();};
 window.addEventListener('click',ev=>{const row=ev.target.closest('.device-holder .v3-draggable');if(!row||!mode)return;ev.preventDefault();ev.stopImmediatePropagation();if(mode==='select'){selected.has(row.dataset.dragId)?selected.delete(row.dataset.dragId):selected.add(row.dataset.dragId);draw();}},true);
 window.addEventListener('keydown',ev=>{if(ev.key==='Escape'&&mode){ev.preventDefault();if(mode==='order')restore();reset();renderKeepingScroll();}},true);
 P.render();
})();

/* Compact playlist actions while scrolling; preserve accessible names. */
(()=>{
 function sync(body){
 const tools=body?.querySelector(':scope > .review-tools');
 if(tools)tools.classList.toggle('list-header-scrolled',body.scrollTop>0 && tools.getBoundingClientRect().top<=body.getBoundingClientRect().top+6);
 const bar=body?.querySelector(':scope > .v4-top-actions.pl-action-row, :scope > .v3-list-tools.pl-action-row');if(!bar)return;
 const order=bar.querySelector('.pl-order-trigger'),add=bar.querySelector('.v4-playlist-create,[data-v3="add-source"]');
 if(order&&!order.querySelector('.pl-action-label')){order.innerHTML='<span aria-hidden="true">↕</span><span class="pl-action-label">순서 변경</span>';order.setAttribute('aria-label','순서 변경');order.title='순서 변경';}
 if(add&&!add.querySelector('.pl-action-label')){for(const n of [...add.childNodes])if(n.nodeType===3)n.remove();const label=document.createElement('span');label.className='pl-action-label';const title=add.matches('.v4-playlist-create')?'새 플레이리스트':'곡 추가';label.textContent=title;if(!add.querySelector('svg')){const plus=document.createElement('span');plus.className='pl-add-symbol';plus.textContent='+';plus.setAttribute('aria-hidden','true');add.append(plus);}add.append(label);add.setAttribute('aria-label',title);add.title=title;}
 bar.classList.toggle('pl-actions-compact',body.scrollTop>12);
 }
 document.addEventListener('scroll',ev=>{if(ev.target.matches?.('.device-holder .phone-body'))sync(ev.target);},true);
 const prev=window.EDIT_UI.afterRender;window.EDIT_UI.afterRender=function(...args){prev?.apply(this,args);sync(document.querySelector('.device-holder .phone-body'));};
 sync(document.querySelector('.device-holder .phone-body'));
})();

/* Extra prototype-only candidates for scrolling and reorder review. */
(()=>{const F=window.FLOW,list=F.playlists.get('playlist-detail');if(!list)return;
 for(let i=3;i<=30;i++){const number=String(99000+i),key='tj:'+number,id='preview-scroll-'+i;if(list.items.some(x=>x.id===id))continue;
 const candidate={brand:'TJ',number,title:`테스트 곡 ${String(i).padStart(2,'0')}`,artist:'시안 가수'};
 F.catalog.set('TJ:'+number,candidate);list.items.push({id,key,candidate});}
 window.Prototype.render();
})();

// Preserve old preview links while using the shared recording song picker.
if(window.Prototype.state.screen==='v3-record-source'){
 window.Prototype.go('draft');window.FLOW.ensureDraft(window.FLOW.screenMap.get('draft'));
 window.FLOW.draft.source='draft';window.FLOW.ui.context={draft:'draft',source:'draft'};
 window.FLOW.popup={kind:'record-source'};window.Prototype.render();
}

/* One validation source for recording save and visible missing-field guidance. */
(()=>{
 const F=window.FLOW,P=window.Prototype;
 F.draftMissingFields=()=>{const d=F.draft,song=F.songs.get(d?.songId),missing=[];
 if(!song?.active)missing.push('곡 선택');else{if(!song.title?.trim())missing.push('곡 제목');if(!song.artist?.trim())missing.push('가수');}
 if(!d?.key)missing.push('키');if(!d?.version)missing.push('버전');return missing;
 };
 const save=F.saveDraft;F.saveDraft=function(){const missing=F.draftMissingFields();if(missing.length){F.draft.error=missing.join(' · ')+' 항목을 입력해 주세요.';return null;}return save.apply(this,arguments);};
 const prev=window.EDIT_UI.afterRender;window.EDIT_UI.afterRender=function(...args){prev?.apply(this,args);const r=document.querySelector('.device-holder .phone'),button=r?.querySelector('[data-flow="save-record"]');if(!button)return;
 r.querySelectorAll('.draft-missing-hint').forEach(n=>n.remove());const missing=F.draftMissingFields();button.disabled=missing.length>0;
 if(missing.length){const hint=document.createElement('div');hint.className='draft-missing-hint';hint.id='draft-missing-hint';hint.setAttribute('role','status');hint.textContent='아직 입력하지 않았어요: '+missing.join(' · ');button.before(hint);button.setAttribute('aria-describedby',hint.id);
 const songButton=r.querySelector('[data-v3="record-source"]');if(missing.includes('곡 선택')&&songButton){songButton.classList.add('draft-required-field');songButton.setAttribute('aria-label','곡 선택 · 필수 입력');const badge=document.createElement('small');badge.className='draft-missing-hint draft-required-label';badge.textContent='선택 필요';songButton.append(badge);}}
 };
 P.render();
})();

/* Recording roles and representative review use the same recording card. */
(() => {
 const F=window.FLOW,P=window.Prototype,R=window.RENDER,e=R.esc,base=R.phone;
 let review=null;
 const screen={id:'representative-review',name:'대표 녹음 확인',tab:'songs',back:'live-representative',group:'03 내 곡',blocks:[]};
 F.addScreen(screen);P.map.set(screen.id,screen);
 R.phone=function(view,interactive=true){
   const t=document.createElement('template');t.innerHTML=base(view,interactive);
   const phone=t.content.querySelector('.phone'),body=phone?.querySelector('.phone-body');if(!body)return t.innerHTML;
   const song=F.songs.get(F.songScreens.get(view.id));
   if(song){const roles=F.roles(song.id),names={'대표 녹음':'representative','최신 녹음':'latest','최저 티어 녹음':'lowest'};
     for(const old of body.querySelectorAll('.flow-role-card>.flow-role-row')){const name=old.querySelector('strong')?.textContent,r=roles[names[name]];if(!r)continue;
       const section=document.createElement('section');section.className='record-role-section';const head=old.cloneNode(true);head.innerHTML='<strong>'+e(name)+'</strong><span>'+(names[name]==='representative'?'변경':'›')+'</span>';section.append(head);section.insertAdjacentHTML('beforeend',R.recordCard(r));
       const copy=section.querySelector('.v3-record-copy');delete copy.dataset.v3;copy.dataset.to=F.recordRoute(r.id);old.replaceWith(section);
     }
   }
   if(view.id==='live-representative')for(const old of body.querySelectorAll('[data-flow="representative"]')){const r=F.recordings.get(old.dataset.record);if(!r)continue;delete old.dataset.flow;old.dataset.repPreview=r.id;old.className='representative-choice';old.innerHTML='<span><strong>'+e(r.title)+'</strong><small>'+e(String(r.at).slice(0,4)+'.'+String(r.at).slice(4,6)+'.'+String(r.at).slice(6,8)+' '+String(r.at).slice(8,10)+':'+String(r.at).slice(10,12)+' · '+F.renderHelpers.duration(r.duration)+' · '+r.tier)+'</small></span><span>›</span>';}
   if(view.id===screen.id){const r=F.recordings.get(review);if(r){const card=document.createElement('template');card.innerHTML=R.recordCard(r);const at=card.content.querySelector('time')?.textContent||'';const available=r.local||r.cloud==='보관됨';body.innerHTML='<section class="song-meta"><h3>'+e(r.title)+'</h3><p>'+e(r.artist)+'</p><div class="representative-info"><span>'+e(r.version)+'</span><span class="key '+(r.key.startsWith('여')?'female':r.key.startsWith('남')?'male':'')+'">'+e(r.key)+'</span><span>녹음 티어: '+e(r.tier)+'</span></div><p>'+e(at)+'</p><p>'+e(F.renderHelpers.duration(r.duration))+'</p></section><section class="song-meta"><p>'+e(window.X.fileState(r))+'</p><button type="button" class="command secondary" data-v3="record-play" data-record="'+e(r.id)+'" '+(available?'':'disabled')+'>재생</button></section><section class="song-meta"><h3>녹음 당시 메모</h3><p>'+e(r.note||'작성한 메모가 없어요.')+'</p></section><button type="button" class="command primary" data-rep-confirm>이 녹음을 대표로 지정</button><button type="button" class="command secondary" data-rep-cancel>목록으로 돌아가기</button>';}}

   return t.innerHTML;
 };
 document.addEventListener('click',event=>{const t=event.target.closest('[data-rep-preview],[data-rep-confirm],[data-rep-cancel]');if(!t)return;event.preventDefault();event.stopImmediatePropagation();
   if(t.hasAttribute('data-rep-preview')){review=t.dataset.repPreview;P.go(screen.id);}
   else if(t.hasAttribute('data-rep-cancel'))P.back();
   else{const r=F.recordings.get(review);if(r&&F.songs.get(r.songId)?.active){F.setRepresentative(r.songId,r.id);P.returnTo(F.songRoute(r.songId));}}
 },true);
 P.render();
})();

/* Recording details mirror the song information layout; actions live in one menu. */
(() => {
 const F=window.FLOW,P=window.Prototype,R=window.RENDER,e=R.esc,base=R.phone;
 R.phone=function(view,interactive=true){
   const html=base(view,interactive),r=F.recordFor(view);if(!r||view.name!=='녹음 상세')return html;
   const t=document.createElement('template');t.innerHTML=html;const body=t.content.querySelector('.phone-body');if(!body)return html;
   const at=String(r.at),date=at.slice(0,4)+'.'+at.slice(4,6)+'.'+at.slice(6,8)+' '+at.slice(8,10)+':'+at.slice(10,12);
   const song=F.songs.get(r.songId);
   body.innerHTML='<header class="record-detail-hero"><h3>'+e(r.title)+'</h3><p>'+e(r.artist)+'</p><small>'+e(date+' · '+F.renderHelpers.duration(r.duration))+'</small></header>'+
     '<div class="record-detail-actions"><button type="button" class="v3-more" data-record-menu aria-label="녹음 메뉴" aria-expanded="false">⋮</button><div class="record-detail-menu" role="menu" hidden><button role="menuitem" type="button" data-ui="record-manage" data-record="'+e(r.id)+'">보관 관리</button><button role="menuitem" type="button" data-to="record-delete">삭제</button></div></div>'+
     '<section class="song-meta"><div class="song-meta-heading"><h3>녹음 정보</h3><button type="button" class="song-edit-link" data-x="edit-record" data-id="'+e(r.id)+'">정보 수정</button></div><dl><div><dt>버전</dt><dd>'+e(r.version)+'</dd></div><div><dt>키</dt><dd>'+e(r.key)+'</dd></div><div><dt>녹음 티어</dt><dd>'+e(r.tier)+'</dd></div></dl></section>'+
     '<section class="song-meta"><h3>컨디션과 태그</h3><p>컨디션: '+e(r.condition||'미선택')+'</p><p>태그: '+e(r.tags?.join(', ')||'없음')+'</p></section>'+
     '<section class="song-meta"><h3>메모</h3><p>'+e(r.note||'아직 작성하지 않았어요.')+'</p></section>'+
     '<section class="song-meta"><h3>연결 곡</h3><p>'+e(r.songId?'등록된 내 곡에 연결됨':'곡 미연결 녹음')+'</p><button type="button" class="flow-text-button" data-x="relink" data-id="'+e(r.id)+'">곡 연결 변경</button>'+(r.songId?'<button type="button" class="flow-text-button" data-flow="linked-song" data-song="'+e(r.songId)+'">연결된 곡 보기</button><button type="button" class="flow-text-button" data-flow="toggle-representative" data-record="'+e(r.id)+'">'+(song?.representative===r.id?'대표 녹음 해제':'대표 녹음으로 지정')+'</button>':'')+'</section>';
   return t.innerHTML;
 };
 document.addEventListener('click',event=>{const toggle=event.target.closest('[data-record-menu]');if(!toggle)return;event.preventDefault();event.stopImmediatePropagation();const menu=toggle.parentElement.querySelector('[role="menu"]');menu.hidden=!menu.hidden;toggle.setAttribute('aria-expanded',String(!menu.hidden));},true);
 P.render();
})();

/* Detail sections open focused editors; cancel leaves the source untouched. */
(() => {
 const F=window.FLOW,P=window.Prototype,R=window.RENDER,e=R.esc,base=R.phone;
 const screen={id:'detail-section-edit',name:'메모 수정',tab:'songs',group:'상세 수정',blocks:[]};
 F.addScreen(screen);P.map.set(screen.id,screen);let target=null;
 R.phone=function(view,interactive=true){
  const t=document.createElement('template');t.innerHTML=base(view,interactive);const body=t.content.querySelector('.phone-body');if(!body)return t.innerHTML;
  if(view.id===screen.id&&target){
   const r=(target.type==='song'?F.songs:F.recordings).get(target.id);if(!r)return t.innerHTML;
   const choices=[...new Set(['좋음','보통','피곤함',r.condition].filter(Boolean))];const tags=[...new Set(['고음','호흡','발음',...(r.tags||[])])];
   body.innerHTML='<form class="x-form" onsubmit="return false">'+(target.field==='note'?'<label>메모<textarea name="note" maxlength="2000">'+e(r.note||'')+'</textarea></label>':'<label>컨디션<select name="condition"><option value="">선택 안 함</option>'+choices.map(v=>'<option '+(v===r.condition?'selected':'')+'>'+e(v)+'</option>').join('')+'</select></label><fieldset><legend>태그</legend>'+tags.map(v=>'<label><input type="checkbox" name="tags" value="'+e(v)+'" '+(r.tags?.includes(v)?'checked':'')+'>'+e(v)+'</label>').join('')+'</fieldset>')+'<button type="button" class="command primary" data-section-save>변경 저장</button><button type="button" class="command secondary" data-section-cancel>취소</button></form>';
  }else{
   const r=F.recordFor(view),s=F.songFor(view),record=r&&view.name==='녹음 상세';
   if(record||s&&view.name==='곡 상세')for(const panel of body.querySelectorAll('.song-meta,.field')){
    const title=panel.querySelector('h3,.field-label,label,small')?.textContent?.trim();
    if(title==='메모'||title==='컨디션과 태그'&&record){panel.dataset.sectionEdit=title==='메모'?'note':'classifications';panel.dataset.sectionType=record?'record':'song';panel.dataset.sectionId=(record?r:s).id;panel.tabIndex=0;panel.setAttribute('role','button');panel.setAttribute('aria-label',title+' 수정');}
   }
  }return t.innerHTML;
 };
 const activate=event=>{const button=event.target.closest('[data-section-edit],[data-section-save],[data-section-cancel]');if(!button)return;event.preventDefault();event.stopImmediatePropagation();
  if(button.hasAttribute('data-section-edit')){target={id:button.dataset.sectionId,type:button.dataset.sectionType,field:button.dataset.sectionEdit};screen.name=target.field==='note'?'메모 수정':'컨디션과 태그';P.go(screen.id);}
  else if(button.hasAttribute('data-section-cancel'))P.back();
  else{const form=document.querySelector('.device-holder .x-form'),data=new FormData(form),r=(target.type==='song'?F.songs:F.recordings).get(target.id);if(target.field==='note')r.note=String(data.get('note')||'');else{r.condition=data.get('condition');r.tags=data.getAll('tags');}P.back();}
 };
 document.addEventListener('click',activate,true);document.addEventListener('keydown',event=>{if(['Enter',' '].includes(event.key)&&event.target.matches('[data-section-edit]'))activate(event);},true);
 P.render();
})();
