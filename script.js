// OpenClaw Dashboard Script

var _initDone = false;
async function init() {
  if (_initDone) return;
  _initDone = true;

  const BASE = '.';
  let status = null, skills = null;

  // Load data
  try {
    const [s, sk] = await Promise.all([
      fetch(BASE + '/data/status.json').then(r => r.ok ? r.json() : null),
      fetch(BASE + '/data/skills.json').then(r => r.ok ? r.json() : null)
    ]);
    status = s;
    skills = sk;
  } catch(e) {
    console.error('Load failed:', e);
  }

  // Hide loader
  const loading = document.getElementById('loading');
  if (loading) { loading.classList.add('hidden'); setTimeout(() => loading.remove(), 400); }

  if (!status) {
    document.body.insertAdjacentHTML('beforeend',
      '<div style="padding:24px;text-align:center;color:var(--yellow)">' +
      '<p>⚠️ 数据加载失败（GitHub Pages 在国内可能需要代理）</p>' +
      '<p style="font-size:0.8rem;color:var(--text-dim);margin-top:8px">请尝试 VPN 或刷新重试</p></div>');
    return;
  }

  document.getElementById('update-time').textContent =
    '最后更新：' + status.datetime + ' · 每小时自动刷新';

  // Status row
  var items = [
    { label: 'Gateway', val: status.gatewayState, ok: status.gatewayState === 'local' },
    { label: 'Sessions', val: status.sessions, ok: status.sessions > 0 },
    { label: 'Skills', val: status.skillsCount, ok: status.skillsCount > 0 },
    { label: '短期记忆', val: status.shortTermCount || 0, ok: true },
    { label: '永久记忆', val: status.permanentCount || 0, ok: true },
    { label: '更新', val: status.updateAvailable ? '可用' : '最新', ok: !status.updateAvailable, warn: !!status.updateAvailable }
  ];

  var row = document.getElementById('status-row');
  row.innerHTML = items.map(function(i) {
    var dot = '<span class="dot ' + (i.warn ? 'yellow' : i.ok ? 'green' : 'red') + '"></span>';
    return '<div class="status-item">' + dot + ' ' + i.label + ': <strong>' + i.val + '</strong></div>';
  }).join('');

  // Cards
  document.getElementById('val-sessions').textContent = status.sessions;
  document.getElementById('sub-sessions').textContent = 'Agent数量: ' + status.agents;
  document.getElementById('val-skills').textContent = status.skillsCount;
  document.getElementById('sub-skills').textContent = status.skillsList ? status.skillsList.split(',').slice(0,3).join(', ') + '...' : '无数据';
  document.getElementById('val-memory').textContent = status.shortTermCount || 0;
  document.getElementById('val-perm').textContent = status.permanentCount || 0;

  var memList = (status.memoryList || '').split(',').filter(Boolean);
  document.getElementById('mem-count').textContent = memList.length;
  document.getElementById('memory-list').innerHTML = memList.length > 0 ?
    memList.map(function(m) { return '<div class="memory-entry">📄 ' + m + '</div>'; }).join('') :
    '<div class="memory-entry" style="color:var(--text-dim)">暂无短期记忆</div>';

  var permList = (status.permanentList || '').split(',').filter(Boolean);
  document.getElementById('perm-count').textContent = permList.length;
  document.getElementById('perm-count').style.background = 'var(--accent2)';
  document.getElementById('permanent-list').innerHTML = permList.length > 0 ?
    permList.map(function(m) { return '<div class="memory-entry">💎 ' + m + '</div>'; }).join('') :
    '<div class="memory-entry" style="color:var(--text-dim)">暂无永久记忆</div>';

  // Skills
  if (skills && skills.skills && skills.skills.length > 0) {
    var skillArr = skills.skills;
    document.getElementById('skill-count').textContent = skillArr.length;
    document.getElementById('skills-list').innerHTML = skillArr.map(function(s) {
      var name = typeof s === 'object' ? s.name : s;
      var desc = typeof s === 'object' ? (s.desc || '') : '';
      return '<div class="skill-tag" title="' + (desc || name) + '">' +
             '<div class="skill-name">' + name + '</div>' +
             (desc ? '<div class="skill-desc">' + desc + '</div>' : '') +
             '</div>';
    }).join('');
  } else {
    var arr = status.skillsList ? status.skillsList.split(',').filter(Boolean) : [];
    document.getElementById('skill-count').textContent = arr.length;
    document.getElementById('skills-list').innerHTML = arr.map(function(s) {
      return '<div class="skill-tag"><div class="skill-name">' + s + '</div></div>';
    }).join('');
  }

  // Today memory
  if (status.todayMemory && status.todayMemory.trim().length > 10) {
    document.getElementById('today-section').style.display = 'block';
    document.getElementById('today-memory').textContent = status.todayMemory;
  }

  // Charts
  var historyText = '';
  try {
    historyText = await fetch(BASE + '/data/history_recent.jsonl').then(function(r) { return r.text(); });
  } catch(e) {}

  var history = [];
  if (historyText) {
    var lines = historyText.trim().split('\n');
    for (var i = 0; i < lines.length; i++) {
      try { history.push(JSON.parse(lines[i])); } catch(e) {}
    }
  }
  if (history.length === 0) history.push(status);

  var labels = history.map(function(h) {
    var d = new Date(h.timestamp * 1000);
    return (d.getMonth() + 1) + '/' + d.getDate() + ' ' + d.getHours() + ':00';
  }).reverse();

  var sessionData = history.map(function(h) { return h.sessions || 0; }).reverse();
  var skillsData = history.map(function(h) { return h.skillsCount || 0; }).reverse();

  var chartOpts = {
    responsive: true,
    maintainAspectRatio: true,
    plugins: { legend: { display: false } },
    scales: {
      x: { ticks: { color: '#71767b', font: { size: 10 } }, grid: { color: '#1c2733' } },
      y: { ticks: { color: '#71767b' }, grid: { color: '#1c2733' }, beginAtZero: true }
    }
  };

  if (typeof Chart !== 'undefined') {
    // Destroy existing charts if any
    ['chart-sessions', 'chart-skills'].forEach(function(id) {
      var existing = Chart.getChart(id);
      if (existing) existing.destroy();
    });
    new Chart(document.getElementById('chart-sessions'), {
      type: 'line',
      data: {
        labels: labels,
        datasets: [{ data: sessionData, borderColor: '#00d4aa', backgroundColor: 'rgba(0,212,170,0.1)', fill: true, tension: 0.4, pointRadius: 2 }]
      },
      options: chartOpts
    });

    new Chart(document.getElementById('chart-skills'), {
      type: 'bar',
      data: {
        labels: labels,
        datasets: [{ data: skillsData, backgroundColor: '#7c5cff', borderRadius: 4 }]
      },
      options: chartOpts
    });
  }
}

if (document.readyState === 'loading') {
  document.addEventListener('DOMContentLoaded', init);
} else {
  init();
}
