
## Initial setup
1. git clone git@github.com:pranavgore09/me.git
2. cd me
3. git submodule update --init --recursive
4. Git config changes in main repo
    - git config --add --local core.sshCommand 'ssh -i ~/.ssh/pranavgore09_personal'
    - git config --local user.name "Pranav Gore"
    - git config --local user.email "pranavgore09@gmail.com"

## Local Development
1. cd me
2. make dev
3. visit http://localhost:1313

## Deploy
The site is hosted on Cloudflare Pages at https://pranavgore.com. Pushing to the `master` branch triggers a Cloudflare build and deploy automatically, no manual deploy step needed.

Note: `public/` is a submodule pointing to the old `pranavgore09.github.io` GitHub Pages repo. That site is no longer maintained and now just redirects to pranavgore.com.
