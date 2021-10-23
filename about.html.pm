#lang pollen

◊(define-meta title "About")

◊h2{About the author}

◊div{
  ◊img[#:class "portrait" #:src "/images/portrait.jpg" #:alt "author's portrait"]{}
  ◊p{ Hi there!}

  ◊p{
  My name is Roman Kashitsyn.
  I'm a software engineer at ◊a[#:href "dfinity.org"]{dfinity}, where I have been working on orthogonal persistence, state snapshotting, state certification, state sync protocol, message routing, and much more.
  I have also co-authored a few relatively popular ◊a[#:href "https://medium.com/dfinity/software-canisters-an-evolution-of-smart-contracts-internet-computer-f1f92f1bfffb"]{canisters}: registry, ledger, internet identity backend, and certified assets canister.
  }
  ◊p{
    Before ◊span[#:class "smallcaps"]{dfinity}, I worked on large-scale distributed systems at ◊a[#:href "https://shopping.google.com/"]{Google.Shopping} and ◊a[#:href "https://yandex.ru/maps"]{Yandex.Maps}.
  }
}

◊h2{About this website}

◊p{
  This website is my personal blog.
  It doesn't necessary reflect the views of my employer.
}

◊h2{What does "mmap" mean?}
◊p{
  "Mmap" stands for ◊a[#:href "https://en.wikipedia.org/wiki/Mmap"]{memory-mapped file I/O}.
  This ancient technology is a beam of light in the murk of the modern technological world darkened by unnecessary complexity and layers of abstractions.
  I like ◊a[#:href "https://www.man7.org/linux/man-pages/man2/mmap.2.html"]{mmap} so much that I called my blog after it.
}