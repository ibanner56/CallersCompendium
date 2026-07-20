/* Caller's Compendium — landing page behaviour.
 *
 * The download section is populated LIVE from the update manifest that the
 * release pipeline already publishes to this same origin
 * (tools/release/publish_pages_manifest.sh -> gh-pages/beta.json). That means
 * versions, links, sizes and checksums stay correct every release with no edits
 * to this page. If the fetch fails we fall back to the Releases page.
 */
(function () {
  "use strict";

  var MANIFEST = "beta.json"; // relative to the site root -> …/CallersCompendium/beta.json
  var RELEASES = "https://github.com/ibanner56/CallersCompendium/releases";

  // Presentation metadata per platform id used in the manifest artifacts.
  var PLATFORMS = {
    windows: { label: "Windows", order: 1, icon: iconWindows },
    macos:   { label: "macOS",   order: 2, icon: iconApple },
    linux:   { label: "Linux",   order: 3, icon: iconLinux },
    android: { label: "Android", order: 4, icon: iconAndroid }
  };

  document.addEventListener("DOMContentLoaded", function () {
    loadManifest();
  });

  function loadManifest() {
    fetch(MANIFEST, { cache: "no-cache" })
      .then(function (r) {
        if (!r.ok) throw new Error("manifest HTTP " + r.status);
        return r.json();
      })
      .then(render)
      .catch(function () {
        renderFallback();
      });
  }

  function render(manifest) {
    var version = manifest && manifest.version ? manifest.version : null;
    if (version) {
      setText("hero-version", "v" + version);
      setText("hero-status", "First public beta is live — v" + version);
      var line = document.getElementById("dl-version-line");
      if (line) {
        line.textContent = "Version " + version;
        var when = formatDate(manifest.pubDate);
        if (when) line.textContent += " · released " + when;
      }
    }

    var grid = document.getElementById("download-grid");
    if (!grid) return;

    var artifacts = (manifest && manifest.artifacts) || [];
    if (!artifacts.length) {
      renderFallback();
      return;
    }

    artifacts.sort(function (a, b) {
      return orderOf(a.platform) - orderOf(b.platform);
    });

    grid.innerHTML = "";
    grid.setAttribute("data-state", "ready");

    artifacts.forEach(function (art) {
      var meta = PLATFORMS[art.platform] || { label: art.platform, icon: null };
      var card = el("div", "dl-card");

      var head = el("div", "dl-os");
      if (meta.icon) head.appendChild(meta.icon());
      head.appendChild(document.createTextNode(meta.label));
      if (art.arch) {
        var arch = el("span", "dl-arch");
        arch.textContent = art.arch;
        head.appendChild(arch);
      }
      card.appendChild(head);

      var meta2 = el("p", "dl-meta");
      meta2.textContent = [fileType(art.url), formatSize(art.size)]
        .filter(Boolean)
        .join(" · ");
      card.appendChild(meta2);

      if (art.sha256) {
        var sha = el("p", "dl-sha");
        sha.title = "SHA-256 checksum";
        sha.textContent = "sha256 " + shorten(art.sha256);
        card.appendChild(sha);
      }

      var link = el("a", "btn btn-primary");
      link.href = art.url;
      link.rel = "noopener";
      link.textContent = "Download";
      link.setAttribute(
        "aria-label",
        "Download Caller's Compendium for " + meta.label + (art.arch ? " (" + art.arch + ")" : "")
      );
      card.appendChild(link);

      grid.appendChild(card);
    });
  }

  function renderFallback() {
    var grid = document.getElementById("download-grid");
    if (!grid) return;
    grid.setAttribute("data-state", "error");
    grid.innerHTML = "";
    var p = el("p", "dl-error");
    p.innerHTML =
      "Couldn't load the live release list. Grab the latest builds directly from the " +
      '<a href="' + RELEASES + '" rel="noopener">Releases page</a>.';
    grid.appendChild(p);
  }

  /* ---------- helpers ---------- */

  function orderOf(platform) {
    var m = PLATFORMS[platform];
    return m && m.order ? m.order : 99;
  }

  function fileType(url) {
    if (!url) return "";
    var m = /\.([a-z0-9]+)(?:\?.*)?$/i.exec(url);
    if (!m) return "";
    var ext = m[1].toLowerCase();
    var names = {
      exe: "Installer (.exe)",
      msix: "Installer (.msix)",
      dmg: "Disk image (.dmg)",
      zip: "Archive (.zip)",
      appimage: "AppImage",
      apk: "Android package (.apk)",
      "tar.gz": "Archive (.tar.gz)"
    };
    return names[ext] || ("." + ext);
  }

  function formatSize(bytes) {
    if (!bytes || isNaN(bytes)) return "";
    var mb = bytes / (1024 * 1024);
    if (mb >= 1024) return (mb / 1024).toFixed(1) + " GB";
    if (mb >= 10) return Math.round(mb) + " MB";
    return mb.toFixed(1) + " MB";
  }

  function formatDate(iso) {
    if (!iso) return "";
    var d = new Date(iso);
    if (isNaN(d.getTime())) return "";
    try {
      return d.toLocaleDateString(undefined, { year: "numeric", month: "long", day: "numeric" });
    } catch (e) {
      return d.toISOString().slice(0, 10);
    }
  }

  function shorten(sha) {
    return sha.length > 20 ? sha.slice(0, 10) + "…" + sha.slice(-6) : sha;
  }

  function setText(id, text) {
    var node = document.getElementById(id);
    if (node) node.textContent = text;
  }

  function el(tag, className) {
    var node = document.createElement(tag);
    if (className) node.className = className;
    return node;
  }

  /* ---------- inline SVG icons (currentColor via .dl-os-icon) ---------- */

  function svg(path) {
    var ns = "http://www.w3.org/2000/svg";
    var s = document.createElementNS(ns, "svg");
    s.setAttribute("viewBox", "0 0 24 24");
    s.setAttribute("class", "dl-os-icon");
    s.setAttribute("aria-hidden", "true");
    s.setAttribute("fill", "currentColor");
    var p = document.createElementNS(ns, "path");
    p.setAttribute("d", path);
    s.appendChild(p);
    return s;
  }
  function iconWindows() { return svg("M3 5.1 10.5 4v7.3H3V5.1Zm0 8.6h7.5V21L3 19.9v-6.2Zm8.8-9.9L21 2.6v8.7h-9.2V3.8Zm0 8.5H21V21l-9.2-1.3v-7.4Z"); }
  function iconApple()   { return svg("M16.4 12.6c0-2.3 1.9-3.4 2-3.5-1.1-1.6-2.8-1.8-3.4-1.8-1.4-.1-2.8.9-3.5.9-.7 0-1.8-.9-3-.8-1.5 0-2.9.9-3.7 2.3-1.6 2.8-.4 6.9 1.1 9.2.7 1.1 1.6 2.4 2.8 2.3 1.1 0 1.5-.7 2.9-.7 1.3 0 1.7.7 2.9.7 1.2 0 2-1.1 2.7-2.2.8-1.2 1.2-2.5 1.2-2.5s-2.3-.9-2.3-3.6ZM14.6 5.6c.6-.8 1-1.9.9-3-.9 0-2 .6-2.7 1.4-.6.7-1.1 1.8-.9 2.9 1 .1 2-.5 2.7-1.3Z"); }
  function iconLinux()   { return svg("M12 2c-2 0-3 1.7-3 3.6 0 1.3.1 2 .1 2.9 0 .8-.7 1.5-1.4 2.7-.8 1.2-1.8 2.5-1.8 4.2 0 .6.2 1 .5 1.4-.2.5-.3 1-.1 1.4.3.6 1 .8 1.8.9.7.1 1.4.4 2 .8.6.4 1.2.6 1.9.6s1.3-.2 1.9-.6c.6-.4 1.3-.7 2-.8.8-.1 1.5-.3 1.8-.9.2-.4.1-.9-.1-1.4.3-.4.5-.8.5-1.4 0-1.7-1-3-1.8-4.2-.7-1.2-1.4-1.9-1.4-2.7 0-.9.1-1.6.1-2.9C15 3.7 14 2 12 2Zm-1.3 4.1c.4 0 .7.4.7.9s-.3.9-.7.9-.7-.4-.7-.9.3-.9.7-.9Zm2.6 0c.4 0 .7.4.7.9s-.3.9-.7.9-.7-.4-.7-.9.3-.9.7-.9Z"); }
  function iconAndroid() { return svg("M6 9.5c-.6 0-1 .4-1 1V16c0 .6.4 1 1 1s1-.4 1-1v-5.5c0-.6-.4-1-1-1Zm12 0c-.6 0-1 .4-1 1V16c0 .6.4 1 1 1s1-.4 1-1v-5.5c0-.6-.4-1-1-1ZM7.5 9v8.2c0 .6.5 1.1 1.1 1.1h.9V21c0 .6.4 1 1 1s1-.4 1-1v-2.7h1V21c0 .6.4 1 1 1s1-.4 1-1v-2.7h.9c.6 0 1.1-.5 1.1-1.1V9h-9Zm7.9-1c-.2-1.2-.9-2.2-1.9-2.9l.8-1.2a.4.4 0 0 0-.6-.5l-.9 1.3c-.5-.2-1.1-.3-1.7-.3s-1.2.1-1.7.3l-.9-1.3a.4.4 0 0 0-.6.5l.8 1.2C7.5 5.8 6.8 6.8 6.6 8h8.8ZM10 6.6c-.3 0-.5-.2-.5-.5s.2-.5.5-.5.5.2.5.5-.2.5-.5.5Zm4 0c-.3 0-.5-.2-.5-.5s.2-.5.5-.5.5.2.5.5-.2.5-.5.5Z"); }
})();
