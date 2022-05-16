---
title: "When & why to use PyAutoGUI"
date: 2022-05-02T06:26:33+05:30
draft: false
---

{{< figure src="/img/for_blogs/pyautogui.png" >}}

PyAutoGUI is one of the framework you can use to test desktop applications. Consider a case where you need to test a flow of the application and it is not in browser, you can go for PyAutoGUI.

Selenium is another framework that comes to the mind when we talk about any type of testing automation but it only supports browser based automation. Selenium can not have control over locally running non-browser app.

We are going to see how we can use PyAutoGUI to build automation script.

### Installation and Documentation Links
[PyAutoGUI Github Repo](https://github.com/asweigart/pyautogui)

[PyAutoGui ReadTheDocs](https://pyautogui.readthedocs.io/en/latest/)

### Examples

#### If you want to drag the mouse cursor to a button and click on it then you can use following snippet.
```
import pyautogui
def move_and_click(x,y):
    # x,y are co=ordinates to move&click
    pyautogui.moveTo(x, y)
    pyautogui.click(x, y)
```

#### Gradually move the mouse cursor and make it look like non-automated :D
```
import pyautogui
# Takes 3 seconds to perform move action
pyautogui.moveTo(x, y, 3)
```

#### If you want to perform double click action on any point.
```
import pyautogui
def double_click(x,y):
    pyautogui.click(clicks=2, x, y)
```

#### If you want to write in a text field.
```
import pyautogui
def write_at_location(x, y, text="HelloWorld"):
    pyautogui.moveTo(x, y)
    pyautogui.typewrite(text)
```

### Fun part, using image recognition

#### Take a screenshot
```
import pyautogui
def screenshot(local_path):
    img = pyautogui.screenshot()
    return img.save(local_path)
```

#### When you can not have X,Y co-ordinates of a button then you need to use image recognition to find that image on screen first and then get its X,Y. Now, use above screenshot and just crop some area that you want to click on (lets call it a button).


```
import pyautogui
def locate_image(image_file):
    location = pyautogui.locateOnScreen(image_file)
    if location:
        print(f'x= {location[0]}, y={location[1]}')
    else:
        print("not_found")
```

#### Also, you can directly get the center of the button
```
import pyautogui
def locate_image(image_file):
    location = pyautogui.locateCenterOnScreen(image_file)
    if location:
        x,y = location[0], location[1]
        pyautogui.moveTo(x, y, 2)
        pyautogui.click(x, y)
    else:
        print("not_found")
```


#### Get resolution of the display
```
import pyautogui
size_x, size_y = pyautogui.size()
print(f'Screen Resolution={size_x}x{size_x}')
```

#### At the core we are going to rely on, image recognition. PyAutoGUI uses Pillow under the hood for image recognition. You can adjust confidence score while it matches the images.
Read more at [this source](https://github.com/asweigart/pyscreeze/blob/0446e87235e0079f591f0c49ece7d487dedc2f9a/pyscreeze/__init__.py#L180)
```
import pyautogui
def locate_image(image_file, confidence=0.999):
    return pyautogui.locateOnScreen(image_file, confidence=confidence)
```

{{< winner >}}
