// 輪播圖片窗（slide 數量會自動偵測，加減 <figure class="slide"> 即可）
(function () {
  const car = document.getElementById('carousel');
  if (!car) return;
  const track = car.querySelector('.slides');
  const slides = car.querySelectorAll('.slide');
  const dotsWrap = car.querySelector('.dots');
  if (!slides.length) return;
  let idx = 0;
  let timer = null;

  slides.forEach((_, i) => {
    const b = document.createElement('button');
    b.setAttribute('aria-label', `第 ${i + 1} 張`);
    b.addEventListener('click', () => { go(i); restart(); });
    dotsWrap.appendChild(b);
  });
  const dots = dotsWrap.querySelectorAll('button');

  function go(i) {
    idx = (i + slides.length) % slides.length;
    track.style.transform = `translateX(${-idx * 100}%)`;
    dots.forEach((d, j) => d.classList.toggle('active', j === idx));
  }
  function play() { timer = setInterval(() => go(idx + 1), 5000); }
  function restart() { clearInterval(timer); play(); }

  car.querySelector('.prev').addEventListener('click', () => { go(idx - 1); restart(); });
  car.querySelector('.next').addEventListener('click', () => { go(idx + 1); restart(); });
  car.addEventListener('mouseenter', () => clearInterval(timer));
  car.addEventListener('mouseleave', play);

  go(0);
  if (slides.length > 1) play();
})();

// 懸浮 AI 聊天
const fab = document.getElementById('chat-fab');
const panel = document.getElementById('chat-panel');
const closeBtn = document.getElementById('chat-close');
const form = document.getElementById('chat-form');
const input = document.getElementById('chat-text');
const sendBtn = document.getElementById('chat-send');
const bodyEl = document.getElementById('chat-body');

const history = []; // {role:'user'|'model', text}

// 預設關閉；以 .open class 控制開合（避免被 CSS display 覆蓋）
function openPanel() {
  panel.classList.add('open');
  fab.textContent = '收合';
  input.focus();
}
function closePanel() {
  panel.classList.remove('open');
  fab.textContent = '問 AI';
}
fab.addEventListener('click', () => {
  panel.classList.contains('open') ? closePanel() : openPanel();
});
closeBtn.addEventListener('click', closePanel);

function addMsg(text, who) {
  const div = document.createElement('div');
  div.className = `msg ${who}`;
  div.textContent = text;
  bodyEl.appendChild(div);
  bodyEl.scrollTop = bodyEl.scrollHeight;
  return div;
}

// 思考中：跳動圓點動畫
function addTyping() {
  const div = document.createElement('div');
  div.className = 'msg bot typing';
  div.innerHTML = '<span class="typing-dots"><span></span><span></span><span></span></span>';
  bodyEl.appendChild(div);
  bodyEl.scrollTop = bodyEl.scrollHeight;
  return div;
}

form.addEventListener('submit', async (e) => {
  e.preventDefault();
  const text = input.value.trim();
  if (!text) return;
  input.value = '';
  sendBtn.disabled = true;
  addMsg(text, 'user');
  const typing = addTyping();

  try {
    const res = await fetch('/api/chat', {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ message: text, history }),
    });
    const data = await res.json();
    typing.remove();
    const answer = data.text || data.error || '目前無法回答，請稍後再試。';
    addMsg(answer, 'bot');
    history.push({ role: 'user', text });
    history.push({ role: 'model', text: answer });
    if (history.length > 16) history.splice(0, history.length - 16);
  } catch (err) {
    typing.remove();
    addMsg('連線發生問題，請稍後再試。', 'bot');
  } finally {
    sendBtn.disabled = false;
    input.focus();
  }
});
