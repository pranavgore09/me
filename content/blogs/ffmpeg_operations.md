---
title: "Video File Operations with FFmpeg"
date: 2020-09-15T11:30:03+00:00
# weight: 1
# aliases: ["/first"]
author: "Me"
showToc: true
TocOpen: false
draft: false
hidemeta: false
comments: false
# description: "Let's learn about simple FFmpeg operations on video files"
disableHLJS: true # to disable highlightjs
disableShare: false
disableHLJS: false
hideSummary: false
searchHidden: true
ShowReadingTime: true
ShowBreadCrumbs: true
ShowPostNavLinks: true
---
{{< figure class="center" src="/img/for_blogs/ffmpeg_logo.png" title="Simple Useful Features of FFmpeg" >}}

In this section we will go over a beautiful tool called as FFmpeg. I have been using FFmpeg for all of my video editing in server in production for more than 4 years now. It is a very reliable, amazing open source project for playing with video editing.


*Small Tip before we jump in*

Before we dive into these cheat sheet, remember that many of the FFmepg options are applicable to input and output files both. Based on where you put the option, FFmpeg decides to apply it for input or output.
Options used before the `-i <input_video>` will be applicable to input file.

---

## Extract Audio
As title suggests, following command will extract only audio from a video file
```
ffmpeg -y -i <video_file> -vn -acodec flac <output_audio_file.flac>
```
Params

* -y : Override output file if already exists
* -i : input file path
* -vn : ignore video
* -acodec : Audio Codec to be used while creating output audio file 
* flac : Audio coding format for lossless compression of digital audio

You should get the audio file after running this command.

## Trim first 5 seconds
```
ffmpeg -ss 00:00:05 -i <input_video> -acodec copy -vcodec copy <output_video>
```

## Trim last 5 seconds
There are couple of different ways to achieve this. I will go with most simple to understand solution.
Run following to find out duration of the meeting.
```
ffprobe <input_video>
```
Find out "Duration" from output of the above command. Let's say that this Duration value is "01:05:10" (1h5m10s).
Now, use `-t` option to re-encode the video and remove last 5 seconds.
```
ffmpeg -y -i <input_video> -t 01:05:05 -c copy <output_video>
```
Try to run it by removing `-c copy`, output will be created using re-encoding.



## Create a thumbnail from the video
FFmpeg supports image/frame creation from the video. For thumbnail creation you need to know time in seconds of the expected thumbnail frame.
Find out Duration of the video from out put of the command below
```
ffprobe <input_video>
```
Now, select Nth second at which you want to create a thumbnail.
Let's say we want to create thumbnail at 100th second, use following to create a thumbnail 
```
ffmpeg -y -i <input_video> -f mjpeg -frames:v 1 -ss 100 thumbnail.jpg
```


## Importance of KeyFrames
Keyframes are important frames which contains more information about the video frame than just the data. In lame terms, it contains start,end,what_changes_in_frame kind of details in it.

Whenever a video is recorded, FFmpeg will insert these keyframes as and when needed. It helps in reducing the FPS and eventually the size of the file.

e.g> If moving traffic is recorded, there will be lot of frame changes which creates lot of keyframes.
 
FFmpeg commands uses these keyframes in many options (read documentation carefully)

e.g> while slicing of the videos - When using copy codec (means, no re-encoding) and if a keyframe is not found at a particular location, FFmpeg will go further to fetch next available keyframe and create a slice at the point.

FFmpeg allows to insert keyframes at dedicated time interval for existing recording.
Following is an exmaple with some complexity to insert a keyframe at every 30th second of meeting.
```
ffmpeg -y -i <input_video> -force_key_frames "expr:gte(t,n_forced*30)" -c:v libx264 -threads 0 -preset faster -pix_fmt yuv420p -c:a flac -ac 1 -crf 25 -f matroska -map_metadata 0:g <output_video>
```
This processing will be time and CPU consuming but it will make sure that every 30th seconds there is a keyframe. Now if we want to trim first or last30 seconds then this will produce accurate results because FFmpeg will find the keyframe at 30th second.


## Reference(s):
- https://ffmpeg.org/ffmpeg.html
- https://superuser.com/a/915369

---
{{< winner >}}