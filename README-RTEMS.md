# Building AdaSockets to target RTEMS. 

Prerequisites
=============
Build and install a working GNAT/RTEMS toolset and a BSP. Make sure
networking and POSIX are enabled.  Detailed instructions are available
online in the RTEMS Wiki at:

    http://www.rtems.org/wiki/index.php/RTEMSAda

Run at least one sample from the RTEMS build (e.g. `hello.exe`
or `sample.exe`) to confirm that RTEMS itself was properly built.

Build and run the RTEMS `hello_world_ada` from the `ada-examples`
package using your GNAT/RTEMS development environment.

If everything is working at this point, then you are ready to
build AdaSockets.

Generate `sockets-constants.ads`
================================
Subdirectory: `rtems`

We will use the RTEMS you installed to build and run a program
called `constants.exe`.  The output of this program needs to be
saved as `sockets-constants.ads`.  To compile this program use
the `Makefile.RTEMS`.

```
% RTEMS_MAKEFILE_PATH=install_path_of_BSP make -f Makefile.RTEMS
```

Then run the program `o-optimize/constants.exe` on the target hardware.
Your saved target board output may end up with DOS style 
CR/LF's.  Run `dos2unix` on the file to get it back to
Unix style.

There is a version of this file generated using `psim` using 
a pre-4.8 CVS snapshot of RTEMS which should work on any target.
You can use this but you would be safer to generate your own.
Consider it an example of how it should look when it works.


Building AdaSockets
===================
Subdirectory: `src`

Now that you have a `sockets-constants.ads`, we can build the
AdaSockets library.  `Makefile.adasockets` is provided for this
step:

```
% RTEMS_MAKEFILE_PATH=install_patch_of_BSP make -f Makefile.RTEMS
```

After the library is compiled, it may be installed using the following:

```
% RTEMS_MAKEFILE_PATH=install_patch_of_BSP make -f Makefile.RTEMS install
```

Building examples
=================
Subdirectory: `examples`

After building the sockets package, build the examples the same way

```
% RTEMS_MAKEFILE_PATH=install_patch_of_BSP make -f Makefile.RTEMS
```

BUGS:

  - stream_listener core dumps if the endian of the `stream_sender` is not
    the same as the listener.
  - multicast does not yet work.  This is probably an RTEMS issue.

