---
title: "Prevent accidental git-push in a simple step"
date: 2018-02-08T14:45:26+05:30
draft: false
description: "A one-line git configuration trick to prevent accidentally pushing to an upstream repository you don't intend to touch."
tags: [git, developer-tools, tips]
---

If you have push access to an upstream repository and want to avoid accidental push, checkout the simple solution below.

{{< figure src="/img/for_blogs/freedom.jpeg" title="Freedom is choosing your responsibility. It’s not having no responsibilities; it’s choosing the ones you want." >}}

Let’s set the context
I will call the original repository as upstream
My fork for that repository will be called as origin
90% of times I push to origin and then create pull request, but few times I push directly to upstream(create new branch or update existing one).


Now, you want to setup your git in such a way that you want to prevent accidental push to upstream but you want to fetch from the same


Let’s add remote first
```
$ git remote add upstream git@github.com:fabric8-services/fabric8-wit.git
```

now let’s check list of remotes
```
$ git remote -v
origin     git@github.com:pranavgore09/fabric8-wit.git (fetch)
origin     git@github.com:pranavgore09/fabric8-wit.git (push)
upstream   git@github.com:fabric8-services/fabric8-wit.git (fetch)
upstream   git@github.com:fabric8-services/fabric8-wit.git (push)
```

See that, when we add a remote, git configures the URL for push and fetch differently. That helps us in blocking push only.


now we just want to run following to update URL for pushing to upstream
```
$ git remote set-url --push upstream DISABLED
```

see the change in remote list now
```
$ git remote -v
origin     git@github.com:pranavgore09/fabric8-wit.git (fetch)
origin     git@github.com:pranavgore09/fabric8-wit.git (push)
upstream   git@github.com:fabric8-services/fabric8-wit.git (fetch)
upstream   DISABLED (push)
```
and when you try to push to upstream it will fail with error saying DISABLED does not appear to be a git repository and that’s how you have just taken care of accidental push to upstream.


Now its the time you want to push to upstream then just do the following
```
$ git remote set-url --push upstream git@github.com:fabric8-services/fabric8-wit.git
```
Don’t forget to reset push URL after you are done pushing 😉

------

### More?
You can add a pre-push hook that will execute defined shell script. Read [git-hooks](https://git-scm.com/book/gr/v2/Customizing-Git-Git-Hooks)


------
Note: This blog is a copy of [my own medium blog](https://medium.com/@pranavgore09/prevent-accidental-git-push-in-a-simple-step-55545d7821a5).



{{< winner >}}
