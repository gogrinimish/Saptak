# Product Website

`site/` is a dependency-free static GitHub Pages product site. It contains only reviewed public copy, the approved icon, and three fictional-data app screenshots. There is no executable JavaScript, analytics, external font request, cookie banner or application service. The homepage includes non-executable JSON-LD describing the app, plus visible FAQs and a linked getting-started guide. The optional support button is a plain external link. The privacy page distinguishes the app from GitHub's hosting and external support services.

## Preview and review

Serve only the site directory, for example `python3 -m http.server 8080 --directory site`, then open http://localhost:8080. Check the home/privacy pages at phone, tablet and desktop widths, keyboard focus, image alternatives, anchors, screenshot loading and horizontal overflow. Honor reduced-motion settings. Changes to this site do not require native app builds.

Keep availability copy accurate. Do not add an App Store/TestFlight download button without a real public URL. Source is MIT-licensed and available at https://github.com/gogrinimish/Saptak. Do not advertise Cast or promise universal document-provider compatibility. Cloud-provider downloads may consume storage.

## GitHub Pages publication

Publish **only the contents of `site/`** to the root of a dedicated `gh-pages` branch. Select that branch with source path `/` in Settings → Pages. Keep `.nojekyll`. Never publish the source repository root or the general `docs/` folder: those contain material unrelated to the website. The source branch retains the editable site; the publishing branch contains just deployable files. Repository visibility must be handled as an explicit, separately authorized source-release decision.

Choose a publishing source appropriate to the repository and hosting plan. See [GitHub's publishing-source instructions](https://docs.github.com/en/pages/getting-started-with-github-pages/configuring-a-publishing-source-for-your-github-pages-site). Publish only reviewed website assets; repository visibility is a separate release decision.

When refreshing screenshots, copy the reviewed `docs/images` versions into the matching `site/assets` paths. The icon comes from `Design/AppIcon.svg`. Confirm the published version matches the reviewed source, and verify home, privacy, stylesheet and image URLs after deployment. The site's optional outgoing links are subject to the destination's privacy practices.

## Public URLs and metadata

The public site is https://gogrinimish.github.io/Saptak/. Canonical links, homepage social-image metadata and sitemap.xml use that project-site URL. Update them together if the host changes. Verify public pages/assets return successful responses without authentication or accidental indexing blocks. Keep structured app facts consistent with visible product behavior and availability. Do not add unverified ratings, offers or download links.

## Typography

Alice Regular (400) is self-hosted in site/assets/fonts throughout website text, including the wordmark, headings, body copy, navigation and controls. Keep its unmodified font file and OFL.txt together, including in deployment and public-source exports. Footer links make the license accessible. Use the real Regular face for all text, with hierarchy expressed through size, spacing and color. Do not synthesize bold or italic Alice faces; the family supplies Regular only. Use font-display: swap so content remains readable during loading. The native apps use the same Alice face; preserve semantic size hierarchy and Dynamic Type in their shared font factory.
