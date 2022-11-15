
<!--#echo json="package.json" key="name" underline="=" -->
streamlink-ubuntu-native
========================
<!--/#echo -->

<!--#echo json="package.json" key="description" -->
A crutch to make streamlink run on Ubuntu.
<!--/#echo -->


⚠ Important caveats ⚠
---------------------

See subchapter "Upgrades" in install instructions below!



Motivation
----------

#### What is streamlink?

[Streamlink](https://github.com/streamlink/streamlink)
is a wonderful tool to help watch live streams.


#### The proper way to install SL

Unfortunately, installing it on Ubuntu LTS usually is a bit cumbersome,
because it pretends to need some python libraries in versions that are
way ahead of Ubuntu LTS versions.

Once upon a time, there were official instructions on how to correctly
install all the required dependencies on Ubuntu, but nowadays the devs
[have given up on Ubuntu][sl-043c63f3]
because it had become way too cumbersome.

  [sl-043c63f3]: https://github.com/streamlink/streamlink/commit/043c63f3825cef2f69cd320220053e9aafb8117f

If you require full feature support and/or any support from the streamlink
community, you may still have a chance if you install it via pip or use
the AppImage, but officially you'll need to use one of the supported OSes.


#### Why do I need those libraries?

For most of the features that I use, you don't strictly need them.
In versions before 2021-06-02 ([breaking commit][sl-b218259f]),
the cumbersome libraries were only used in a few obscure plugins, so an easy
work-around was to just delete those.

  [sl-b218259f]: https://github.com/streamlink/streamlink/commit/b218259f08a16fe328f24ba901a8f207d62415e6


#### Shims for using older libraries

Fortunately, most features of streamlink, don't really need the latest
version of all the libraries.
It could work with other, older libraries that ship with Ubuntu LTS,
but they have different names.

Of course the streamlink devs could add feature detection to accomodate
for lots of operating systems that each have their tiny variations,
but that would blow their project scope out of proportion.
Better leave that task to third party projects – like this one here.



Install
-------

1.  Use Ubuntu 20.04 (focal) or a later LTS version.
1.  Install these apt packages:
    * `python3-isodate`
    * `python3-pycountry`
    * `python3-pycryptodome`
    * `python3-socks`
    * `python3-websocket`
1.  Any paths that you'll have to choose in the next steps
    MUST NOT contain any colon (`:`).
    This also applies for the effective path to which they resolve.
    (The latter is only relevant for paths that contain symlink steps.)
1.  Clone the streamlink repo somewhere.
1.  Clone this repo somewhere.
1.  In your clone of this repo, create a symlink named `sl-repo`
    that points to your local clone of the streamlink repo.
    * In case it's more convenient, you can instead set the SL repo path
      as environment variable `STREAMLINK_REPO_PATH`.
1.  Create a symlink `/usr/local/bin/streamlink` that points to
    `wrapper.sh` from this repo.



### Upgrades

While streamlink should mostly work on native Ubuntu, some features
really do need more recent libraries than Ubuntu's ancient versions:
[List of known broken features](upgrades/known_broken/README.md)

To easily install the required upgrades
for just our streamlink wrapper,
without pip,
and without littering files outside of the `upgrades` directory,
run:&nbsp;`./upgrades/dl.sh`



Usage
-----

```text
$ streamlink --help | head --lines=1
H: Did you clone and symlink the streamlink repo?
E: Not a directory: /tmp/streamlink-ubuntu-native/sl-repo

# After cloning and fixing the symlink:

$ streamlink --help | head --lines=1
usage: streamlink [OPTIONS] <URL> [STREAM]
```



<!--#toc stop="scan" -->



Known issues
------------

* See subchapter "Upgrades" in install instructions.
* Needs more/better tests and docs.




&nbsp;


License
-------
<!--#echo json="package.json" key=".license" -->
ISC
<!--/#echo -->
