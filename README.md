
## Initial setup
1. git clone git@github.com:pranavgore09/me.git
2. cd me
3. git submodule add https://github.com/adityatelange/hugo-PaperMod.git themes/PaperMod --depth=1
4. git submodule update --init --recursive # needed when you reclone your repo (submodules may not get cloned automatically)
5. Open and cleanup `.gitmodules` as needed
6. Git config changes in main repo
    - git config --add --local core.sshCommand 'ssh -i ~/.ssh/pranavgore09_personal'
    - git config --local user.name "Pranav Gore"
    - git config --local user.email "pranavgore09@gmail.com"
7. git clone git@github.com:pranavgore09/pranavgore09.github.io.git ./public
8. cd public
9. Git config changes in public repo
    - git config --add --local core.sshCommand 'ssh -i ~/.ssh/pranavgore09_personal'
    - git config --local user.name "Pranav Gore"
    - git config --local user.email "pranavgore09@gmail.com"

## Local Development
1. cd me
2. make dev
3. visit http://localhost:1313

## Deploy to main site
1. cd me
2. make deploy
