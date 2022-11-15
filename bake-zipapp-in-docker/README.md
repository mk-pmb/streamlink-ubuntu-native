
Bake zipapp in docker
=====================


Mission
-------

Making `pip install` work inside of docker,
in order to make it reproducible,
as well as contain any side effects like temporary files.
Then, also inside the docker container, bake a zipapp
that can be extracted to run outside of the container.



Required tools
--------------

* Ubuntu 20.04 LTS "focal"
* Docker CE (community edition) version 20.10.18 or later



Limitations
-----------

A zipapp cannot contain native binaries as would be used by
the Crypto module.
Fortunately, currently, only a few exotic plugins use the Crypto module,
so a shim should be good enough to run most of streamlink.


















