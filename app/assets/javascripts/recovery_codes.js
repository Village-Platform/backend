// Recovery codes page (admin/authenticators/create): save the codes as a text file or copy them.
// The server keeps only digests, so the file is built here from the codes on the page; this page is
// the only place they ever exist in plain text. The buttons start hidden and appear only when this
// script runs, so without JavaScript the page still shows the codes and nothing broken.
document.addEventListener("DOMContentLoaded", () => {
  const box = document.querySelector("[data-recovery-codes]");
  if (!box) return;

  const codes = Array.from(box.querySelectorAll("[data-code]"), (el) => el.dataset.code);
  const text = () => [box.dataset.header, "", ...codes, ""].join("\n");

  const download = box.querySelector("[data-recovery-download]");
  download.hidden = false;
  download.addEventListener("click", () => {
    // The byte-order mark makes Windows Notepad read the Arabic header as UTF-8.
    const blob = new Blob(["﻿" + text()], { type: "text/plain;charset=utf-8" });
    const url = URL.createObjectURL(blob);
    const link = Object.assign(document.createElement("a"), { href: url, download: box.dataset.filename });
    document.body.append(link);
    link.click();
    link.remove();
    URL.revokeObjectURL(url);
  });

  const copy = box.querySelector("[data-recovery-copy]");
  if (!navigator.clipboard) return; // only on https or localhost
  copy.hidden = false;
  copy.addEventListener("click", async () => {
    await navigator.clipboard.writeText(text());
    copy.textContent = copy.dataset.done;
  });
});
