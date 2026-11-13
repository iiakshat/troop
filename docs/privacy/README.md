# Privacy policy page

`index.html` is the Siren Squad privacy policy as one self-contained page (inline CSS, no scripts,
light and dark). Its text follows `docs/PRIVACY.md`; change both together. Before publishing, fill
in the three `TODO: contact email` spots and the "Last updated" date (see the comment at the top of
the file).

**Hosting (GitHub Pages, free):** on github.com open `iiakshat/troop` → **Settings → Pages** →
Source **Deploy from a branch** → branch **main**, folder **/docs** → Save. After a minute or two the
page is at **https://iiakshat.github.io/troop/privacy/**; paste that URL into the Play Console
(**App content → Privacy policy**) and the AdMob app settings. Note: this account's GitHub Actions is
locked by a billing issue, and branch-based Pages builds also run as an Actions job, so the page may
not publish until billing is fixed. If so, upload `index.html` to any static host instead (Netlify
Drop, Cloudflare Pages, Firebase Hosting or Google Sites); the URL only has to be public, stable and
not a PDF. `docs/.nojekyll` makes Pages serve the folder as plain files (no Jekyll build of the
other docs).
