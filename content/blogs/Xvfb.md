---
title: "X virtual framebuffer (Xvfb)"
date: 2020-04-22T23:53:45+05:30
draft: false
---

Today, let's talk about AWESOME X virtual frame buffer.

If you want to emulate the X server and want your UI apps to render over there then the answer is [Xvfb](https://www.x.org/releases/X11R7.6/doc/man/man1/Xvfb.1.xhtml).
Xvfb uses frame buffer to emulate X server.

Let's install it first
```
sudo apt update
sudo apt install xvfb
```
----
Basic Usage:
```
Xvfb :111 -screen 0 1920x1080x24 & echo $! > /tmp/runxvfb.pid
```
With this command we are creating a new display with 1920x1080 resolution and put the PID info /tmp/runxvfb.pid
":111" is the ID of the new display. We will use ":111" whenever we want to refer to that display.


Verify that display is created and available to use
```
xdpyinfo -display :111 >/dev/null 2>&1 && echo "In use" || echo "Free"
```
It should print "In use", which means ":111" is not available at this moment.

We can again create another display with some other ID, try to create new display with your favourite number

```
Xvfb :10 -screen 0 1920x1080x24 & echo $! > /tmp/runxvfb_2.pid
```
Keep ":" in the format.

You can stop the display with PID we stored earlier
```
kill -9 `cat /tmp/runxvfb.pid`
```

Check all Xvfb displays
```
ps -ef|grep Xvfb
```
This should print out the Xvfb command used while launching the program, there you can check which ID is occupied.

----

Now, let's use the newly created display in our python program
```
DISPLAY=:100 python run.py
```
In the python code, if you invoke selenium driver or any other UI program, it will be rendered on our Xvfb display ":100".
If that display is not reachable for whatever reason, GUI program will fail saying so.



There exists a python package as well for Xvfb

```
from xvfbwrapper import Xvfb
with Xvfb(width=1920, height=1080, colordepth='24+32'):
   pass
```

This will create a Xvfb like we did from shell.

----
### Conclusion:
It is now simple to test UI application, run selenium (check references below) or record screen using ffmpeg and Xvfb.
As per need you can use Xvfb from python or from shell. Super cool to get your hands dirty.


#### References:
- https://www.x.org/releases/X11R7.6/doc/man/man1/Xvfb.1.xhtml
- https://pypi.org/project/xvfbwrapper/
- http://tobyho.com/2015/01/09/headless-browser-testing-xvfb/
- http://elementalselenium.com/tips/38-headless
- https://en.wikipedia.org/wiki/Xvfb


{{< winner >}}