---
title: "Record Screen and Audio using FFmpeg on macOS"
date: 2020-05-12T09:34:21+05:30
draft: false
---

By the end of this blog you will be able to record your screen+audio on macOS.

{{< figure src="/img/for_blogs/ffmpeg_ubuntu.png" title="2 beautiful Open Source softwares" >}}

----
Get started by installing FFmpeg with [brew](https://formulae.brew.sh/formula/ffmpeg). Run following command

```
brew install ffmpeg --with-sdl2 --with-ffplay
(--with-ffplay is optional)
```

Try running `ffmpeg`, you should see some output with version number on first line.
```
ffmpeg version 4.2.2-tessus  https://evermeet.cx/ffmpeg/  Copyright (c) 2000-2019 the FFmpeg developers
  built with Apple clang version 11.0.0 (clang-1100.0.33.16)
  configuration: --cc=/usr/bin/clang --prefix=/opt/ffmpeg --extra-version=tessus --enable-avisynth --enable-fontconfig --enable-gpl --enable-libaom --enable-libass --enable-libbluray --enable-libdav1d --enable-libfreetype --enable-libgsm --enable-libmodplug --enable-libmp3lame --enable-libmysofa --enable-libopencore-amrnb --enable-libopencore-amrwb --enable-libopenh264 --enable-libopenjpeg --enable-libopus --enable-librubberband --enable-libshine --enable-libsnappy --enable-libsoxr --enable-libspeex --enable-libtheora --enable-libtwolame --enable-libvidstab --enable-libvmaf --enable-libvo-amrwbenc --enable-libvorbis --enable-libvpx --enable-libwavpack --enable-libwebp --enable-libx264 --enable-libx265 --enable-libxavs --enable-libxvid --enable-libzimg --enable-libzmq --enable-libzvbi --enable-version3 --pkg-config-flags=--static --disable-ffplay
  libavutil      56. 31.100 / 56. 31.100
  libavcodec     58. 54.100 / 58. 54.100
  libavformat    58. 29.100 / 58. 29.100
  libavdevice    58.  8.100 / 58.  8.100
  libavfilter     7. 57.100 /  7. 57.100
  libswscale      5.  5.100 /  5.  5.100
  libswresample   3.  5.100 /  3.  5.100
  libpostproc    55.  5.100 / 55.  5.100
Hyper fast Audio and Video encoder
usage: ffmpeg [options] [[infile options] -i infile]... {[outfile options] outfile}...

Use -h to get full help or, even better, run 'man ffmpeg'
```
As of this writing I am using version `4.2.2`

---

Let's see which are the AudioVideo devices you have attached to your computer
```
ffmpeg -f avfoundation -list_devices true -i ""
```
you should see some result as following
```
.
.
[AVFoundation input device @ 0x7f85b1a04500] AVFoundation video devices:
[AVFoundation input device @ 0x7f85b1a04500] [0] FaceTime HD Camera
[AVFoundation input device @ 0x7f85b1a04500] [1] Capture screen 0
[AVFoundation input device @ 0x7f85b1a04500] AVFoundation audio devices:
[AVFoundation input device @ 0x7f85b1a04500] [0] Built-in Microphone
```
Note down the device numbers in `[]`. For me I want to record my screen and my microphone audio hence I will use `"1:0"` in following command.
Prepare your combination with syntax `"<screen_device_index>:<audio_device_index>"`


Now, lets record with most minimum setup
```
ffmpeg -y -f avfoundation -i "1:0" output.mkv
```
Explaination for each parameter

-y : overwrite output file if exists

-f : it is one of the [main options](https://ffmpeg.org/ffmpeg.html#toc-Main-options) to ffmpeg, it tells which format to use, here `avfoundation`

-i : Input file. Here, we provide device number's combination that avfoundation will understand and act as input to ffmpeg

output.mkv : output file to store the recording in [Matroska container](https://www.matroska.org/technical/whatis/index.html).


Use following to play the recording in your default player
```
open output.mkv
```
---
In above section, if you do not get proper audio and gets cracking sound or bad audio then checkout [this link](https://stackoverflow.com/questions/35590500/ffmpeg-record-output-audio-for-mac)

Just in case that link is not available(for any reason in future), read following section else skip


Go to your "Spotlight Search" (press cmd+space) and search for "audio midi setup", open it.

In the microphone settings, click on format dropdown, select "bit depth" and change it any one of 16 bit value
(I had to restart once after making this change)

Now, record again using 
```
ffmpeg -y -f avfoundation -i "1:0" output.mkv
```
And verify your recording, hopefully it comes out as expected!

---
### Conclusion:
Now, you can go ahead and put it in a [Makefile](https://www.gnu.org/software/make/manual/make.html) and then with single command like `make record` you can start your recording. Very easy to get started with.



#### Reference(s):
- https://trac.ffmpeg.org/wiki/Capture/Desktop
- https://ffmpeg.org/ffmpeg.html

---




{{< winner >}}
