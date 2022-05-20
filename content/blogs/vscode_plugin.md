---
title: "Writing custom VSCode plugin"
date: 2022-05-20T15:24:16+05:30
draft: false
openLinksNewTab: true
---

I enjoy writing code snippets that eventually works out as a utility to a developer.

{{< figure height=500 width=800 class="center" src="/img/for_blogs/tools.jpg" title="The DevTools!" >}}


Developer tools are small independent code pieces those can be executed on-demand and should not have any side effects.
Recently I have been using Django Admin intensively to add more and more options in list view, detail view to help debugging and developing better.
But about that in some other blog.

Here, I am going to talk about a VSCode plugin that I published.

Market place Link: [Link Opener](https://marketplace.visualstudio.com/items?itemName=pgvscodeextentionpublisher.link-opener)

Github Repository Link: [Link Opener](https://github.com/pranavgore09/link-opener)

### Why?
In recent years I have seen that comments in the code has more and more links to outside resources. Be it a link to google drive where you have store company's strategy to release this feature or be it a stackoverflow link based on which relative code is written.
When I want to open such links I was clicking on each of them one by one while holding ctrl. After a while it became tedious 😀.

My use was not just from documentation, but particularly opening a lot of Django Admin pages for which I had generated URLs via other tools. Bunch of URLs is the input which I will paste in a new page and trigger command to open all these links.

### How to build custom plugin?
[This is](https://code.visualstudio.com/api/get-started/your-first-extension) the document that helped me understand the architecture of plugin development and testing.

I went through [this great tutorial on youtube](https://www.youtube.com/watch?v=q5V4T3o3CXE) at 1.5x speed, I followed the publishing steps from the video while I was writing my own code for the plugin. Shoutout to [WebDevSimplified](https://www.youtube.com/c/WebDevSimplified) channel.

And I designed a logo as well!! (By trying to follow [this](https://www.youtube.com/watch?v=qCaTXvJE4X8) tutorial) 


### How?
If current document has valid links in it then, with a single command you can open all the links at a time in different tabs.
Firefox supports opening multiple tabs in parallel from command line. When Firefox is not installed on system it will open just first link in system's default browser.


### Resources
- Official documentation on custom plugins https://code.visualstudio.com/api/get-started/your-first-extension
- Youtube tutorial on writing+publishing custom plugins https://www.youtube.com/watch?v=q5V4T3o3CXE
- Youtube tutorial to design a logo in GIMP https://www.youtube.com/watch?v=qCaTXvJE4X8


{{< winner >}}
