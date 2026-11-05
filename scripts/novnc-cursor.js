// Android sends no pointer shape, so draw an arrow in the page that follows the mouse over the phone screen.
(function () {
  function start() {
    var arrow = document.createElement('div');
    arrow.id = 'avm_cursor';
    arrow.style.cssText = 'position:fixed;left:0;top:0;width:24px;height:24px;z-index:2147483647;pointer-events:none;display:none;';
    arrow.innerHTML = '<svg xmlns="http://www.w3.org/2000/svg" width="24" height="24" viewBox="0 0 24 24">' +
      '<path d="M1 1 L1 19 L6 14.5 L9.5 22 L12.5 20.7 L9 13.5 L15.5 13.5 Z" fill="#fff" stroke="#000" stroke-width="1.5" stroke-linejoin="round"/></svg>';
    document.body.appendChild(arrow);
    window.addEventListener('mousemove', function (e) {
      var under = document.elementFromPoint(e.clientX, e.clientY);
      // noVNC covers the page with a capture element during a drag, so keep showing the arrow while a button is held.
      if (e.buttons || (under && under.tagName === 'CANVAS')) {
        arrow.style.transform = 'translate(' + (e.clientX - 1) + 'px,' + (e.clientY - 1) + 'px)';
        arrow.style.display = 'block';
      } else {
        arrow.style.display = 'none';
      }
    }, true);
    document.documentElement.addEventListener('mouseleave', function () { arrow.style.display = 'none'; });
  }
  if (document.body) start(); else document.addEventListener('DOMContentLoaded', start);
})();
