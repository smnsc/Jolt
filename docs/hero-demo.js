/* A local, visual-only recording. The original illustration is never modified. */
(() => {
  const stage = document.querySelector('.hero-demo-stage');
  const fallback = stage?.querySelector('.search-demo');
  const toggle = document.querySelector('.hero-demo-toggle');
  if (!stage || !fallback || !toggle) return;

  let demo, observer, frame = 0, previous = null, elapsed = 0;
  let visible = false, playing = false, failed = false;
  const motion = matchMedia('(prefers-reduced-motion: reduce)');
  const restore = () => {
    failed = true;
    cancelAnimationFrame(frame);
    observer?.disconnect();
    stage.classList.remove('is-playing-demo');
    fallback.removeAttribute('aria-hidden');
    demo?.remove();
    toggle.hidden = true;
  };
  const guard = action => (...args) => {
    try { action(...args); } catch { restore(); }
  };

  try {
    demo = fallback.cloneNode(true);
    demo.classList.add('hero-demo-animation');
    demo.setAttribute('aria-label', 'Simulated Jolt demo: search for login issues, type #epic and then @web to narrow results, preview an issue, and copy its link.');
    const query = demo.querySelector('.query-text');
    const scope = demo.querySelector('.scope');
    const rows = [...demo.querySelectorAll('.issue')];
    const footer = demo.querySelector('.demo-footer');
    const issues = [
      ['Fix login redirect', 'DEV-142 · Bug'],
      ['Improve login security', 'DEV-148 · Epic'],
      ['A simpler login experience', 'WEB-87 · Epic'],
      ['Unify the web login flow', 'WEB-92 · Epic'],
      ['Polish the keyboard shortcuts', 'DEV-127 · Task'],
      ['Share an issue with your team', 'WEB-82 · User Story']
    ];
    rows.forEach((row, i) => {
      row.querySelector('strong').textContent = issues[i][0];
      row.querySelector('small').textContent = issues[i][1];
      if (i === 0) {
        const icon = row.querySelector('.issue-icon');
        icon.className = 'issue-icon hero-bug';
        icon.textContent = '●';
      } else if (i < 4) {
        const icon = row.querySelector('.issue-icon');
        icon.className = 'issue-icon epic';
        icon.textContent = 'ϟ';
      }
    });
    rows[3].querySelector('.status').className = 'status progress';
    rows[3].querySelector('.status').innerHTML = '<i>↻</i> In Progress';
    const epic = [...scope.children].find(item => item.textContent === 'Epic');
    const web = [...scope.children].find(item => item.textContent === 'WEB');
    const panel = document.createElement('div');
    panel.className = 'hero-demo-detail';
    panel.innerHTML = '<small>WEB-92 · Epic <span>IN PROGRESS</span></small><h3>Unify the web login flow</h3><p>Give the team a consistent sign-in experience across the website.</p><h4>Acceptance criteria</h4><p>✓ Preserve the session across project switches.</p><p>✓ Return to the last page after signing in.</p>';
    const menu = document.createElement('div');
    menu.className = 'hero-demo-menu';
    menu.innerHTML = '<div>Copy issue key and title</div><div class="chosen">Copy link <span>↵</span></div><div>Open in Jira</div>';
    const cue = document.createElement('div');
    cue.className = 'hero-demo-cue';
    demo.append(panel, menu, cue);
    stage.append(demo);

    let lastScene = '';
    const render = () => {
      const t = (elapsed % 24000) / 1000;
      const typed = (value, start) => value.slice(0, Math.max(0, Math.min(value.length, Math.floor((t - start) * 5))));
      const text = typed('login', 1) + typed(' #epic', 4) + typed(' @web', 8);
      // Keep the previous results while typing; narrow once each shortcut is complete.
      const searched = t >= 2.3;
      const epicFiltered = t >= 5.5;
      const webFiltered = t >= 9.3;
      const selected = t >= 11 ? 3 : epicFiltered ? 2 : 0;
      const preview = t >= 13 && t < 17;
      const actions = t >= 19 && t < 21.5;
      const copied = t >= 21.5 && t < 23;
      const scene = [text, searched, epicFiltered, webFiltered, selected, preview, actions, copied].join('|');
      if (scene === lastScene) return;
      lastScene = scene;
      query.textContent = preview ? '‹  WEB-92' : text || 'Search issues by text, @project, #type…';
      query.classList.toggle('has-query', !!text);
      scope.hidden = preview;
      epic.classList.toggle('hero-filter-active', epicFiltered);
      web.classList.toggle('hero-filter-active', webFiltered);
      rows.forEach((row, i) => {
        row.hidden = preview || (webFiltered ? i !== 2 && i !== 3 : epicFiltered ? i < 1 || i > 3 : searched && i > 3);
        row.classList.toggle('selected', i === selected);
      });
      panel.hidden = !preview;
      menu.hidden = !actions;
      footer.style.visibility = preview ? 'hidden' : '';
      cue.textContent = preview ? '→  Quick Look' : actions ? '⌥ ↵  Actions' : copied ? '✓  Link copied' : t >= 11 ? '↓  Select an issue' : webFiltered ? '2 web epics' : epicFiltered ? '3 epics across projects' : searched ? '4 matching issues' : text ? 'Type to search' : '⌥ J  Open Jolt';
      demo.classList.toggle('hero-copy-done', copied);
    };
    const reveal = () => {
      render();
      stage.classList.add('is-playing-demo');
      fallback.setAttribute('aria-hidden', 'true');
    };
    const tick = guard(now => {
      if (previous !== null) elapsed += Math.min(now - previous, 100);
      previous = now;
      render();
      frame = requestAnimationFrame(tick);
    });
    const sync = () => {
      cancelAnimationFrame(frame);
      previous = null;
      toggle.textContent = playing ? 'Pause demo' : 'Play demo';
      if (!failed && playing && visible && !document.hidden) frame = requestAnimationFrame(tick);
    };
    toggle.addEventListener('click', guard(() => {
      if (failed) return;
      playing = !playing;
      if (playing) reveal();
      sync();
    }));
    document.addEventListener('visibilitychange', guard(sync));
    motion.addEventListener('change', guard(() => {
      if (failed) return;
      playing = !motion.matches;
      if (playing) reveal();
      else {
        stage.classList.remove('is-playing-demo');
        fallback.removeAttribute('aria-hidden');
      }
      sync();
    }));
    observer = new IntersectionObserver(guard(entries => {
      visible = entries[0].isIntersecting;
      sync();
    }), { threshold: 0.15 });
    observer.observe(stage);
    playing = !motion.matches;
    if (playing) reveal();
    toggle.hidden = false;
    sync();
  } catch { restore(); }
})();
