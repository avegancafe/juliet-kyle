// Loaded by the Claude Duet GNOME Web app (setup-kyle-duet-webapp).
// GNOME Web sends a link to the default browser (Zen) only when it's a plain
// link click to another site. Duet opens links in new windows or through
// JavaScript, which keeps them inside the web app. This turns those into
// plain link clicks.
(() => {
  const isOutside = (href) => {
    try {
      const url = new URL(href, location.href);
      return /^https?:$/.test(url.protocol) && url.hostname !== location.hostname;
    } catch {
      return false;
    }
  };

  const openOutside = (href) => {
    const a = document.createElement("a");
    a.href = href;
    document.documentElement.appendChild(a);
    a.click();
    a.remove();
  };

  const onClick = (event) => {
    const link = event.target instanceof Element && event.target.closest("a[href]");
    if (!link || !isOutside(link.href)) return;
    if (!link.target && event.button === 0 && !event.ctrlKey && !event.metaKey && !event.shiftKey) return; // already a plain click
    event.preventDefault();
    event.stopImmediatePropagation();
    openOutside(link.href);
  };
  document.addEventListener("click", onClick, true);
  document.addEventListener("auxclick", onClick, true);

  const open = window.open;
  window.open = function (url, ...rest) {
    if (url && isOutside(String(url))) {
      openOutside(String(url));
      return null;
    }
    return open.call(this, url, ...rest);
  };
})();
