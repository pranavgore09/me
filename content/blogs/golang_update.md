---
title: "Update golang version on Fedora"
date: 2017-10-16T22:40:33+05:30
draft: false
---


Find out where Golang is installed, generally on the fedora it is /usr/local/go Or if you have custom location then check with echo $GOROOT and go to the location and rename go directory using sudo mv go go1.7.3. We keep older version for safety.


Now, go to https://golang.org/dl/ and download suitable version for your system. Lets say downloaded file is in ~/Downloads/ and then execute following (modify paths as required)
```
sudo tar -C /usr/local -xzf ~/Downloads/go1.8.4.linux-amd64.tar.gz
```


And you are done here, just check what go version tells you. (should be the updated version)

{{< figure src="/img/for_blogs/gopher.jpg" title="Happy Gopher." >}}



------
Note: This blog is a copy of [my own medium blog](https://medium.com/@pranavgore09/update-golang-version-on-fedora-da2446240de2).

{{< winner >}}
