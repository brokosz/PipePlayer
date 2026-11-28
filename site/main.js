// One clip plays at a time. Every play button names its clip in
// data-audio; buttons sharing a clip (the hero and its card) stay in step.
(() => {
  const buttons = [...document.querySelectorAll('.play[data-audio]')];
  const audio = new Audio();
  audio.preload = 'none';
  let current = null; // src of the clip loaded into `audio`

  const forClip = (src) => buttons.filter((b) => b.dataset.audio === src);

  function show(src, playing) {
    for (const b of forClip(src)) {
      b.classList.toggle('playing', playing);
      b.setAttribute('aria-label', `${playing ? 'Pause' : 'Play'} ${b.dataset.title}`);
      b.closest('.hero-play')?.classList.toggle('playing', playing);
    }
  }

  function progress(src, fraction) {
    for (const b of forClip(src)) {
      const bar = b.parentElement.querySelector('.bar i');
      if (bar) bar.style.width = `${fraction * 100}%`;
    }
  }

  for (const button of buttons) {
    button.addEventListener('click', () => {
      const src = button.dataset.audio;
      if (src === current && !audio.paused) {
        audio.pause();
        return;
      }
      if (src !== current) {
        if (current) {
          show(current, false);
          progress(current, 0);
        }
        current = src;
        audio.src = src;
      }
      audio.play().catch(() => {}); // failures land in the 'error' handler
    });
  }

  audio.addEventListener('play', () => current && show(current, true));
  audio.addEventListener('pause', () => current && show(current, false));
  audio.addEventListener('timeupdate', () => {
    if (current && audio.duration) progress(current, audio.currentTime / audio.duration);
  });
  audio.addEventListener('ended', () => {
    if (!current) return;
    show(current, false);
    progress(current, 0);
    current = null;
  });
  audio.addEventListener('error', () => {
    if (!current) return;
    show(current, false);
    progress(current, 0);
    for (const b of forClip(current)) {
      b.disabled = true;
      b.title = "Couldn't load this clip";
    }
    current = null;
  });
})();
