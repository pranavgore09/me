---
title: "Exported but Restricted inside `internal` package."
date: 2018-02-28T22:50:31+05:30
draft: false
---


Information about internal package , _ and . imports in Golang!

{{< figure src="/img/for_blogs/restricted.jpeg" >}}


If you come across any package named internal or you write a package with the name internal then it is treated special in Golang world!
Only question to ask about it is, Who can import this internal package?


And the answer is, any file out side the package containing internal package can NOT import internal because the name is self explanatory.
Whereas, any file inside package that contains internal package, can import that internal package.


Ah! Lets quickly see an example.

```
project/feature/A/internal/important.go
project/feature/A/cli/*
project/feature/A/hello.go
project/feature/B/*
project/feature/* (other than A)
```

Say, Package A has internal package. So who can import and use that package?
Any code inside project/feature/A/ can import project/feature/A/internal/
And, any code outside project/feature/A , can NOT import project/feature/A/internal/


Easy and neat, isn’t it?

-----

And while we are talking about imports , let’s see two related things.
1. Import using .
All the exported identifiers will be available in the current file’s block and they can be accessed without any qualifier.
2. Import using _
Only purpose to do so is to have side-effects of importing that package. When any package is imported, it’s init method is invoked (if present) that might have intended good side-effects.


------
Note: This blog is a copy of [my own medium blog](https://medium.com/@pranavgore09/exported-but-restricted-inside-internal-package-354e58469523).

{{< winner >}}
