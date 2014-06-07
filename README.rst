swat-http
%%%%%%%%%

:Version:           1.1.0
:Home page:         https://github.com/sergeii/swat-http
:Author:            Sergei Khoroshilov <kh.sergei@gmail.com>
:License:           The MIT License (http://opensource.org/licenses/MIT)

Description
===========
This is a UnrealScript/SWAT4 package that provides HTTP client capabilities to any other interested third party packages.

Dependencies
============
* `Utils <https://github.com/sergeii/swat-utils>`_ *>=1.0.0*

Installation
============

0. Install the required packages listed above in the **Dependencies** section.

1. Download the compiled binaries or compile the package yourself.

   Every release is accompanied by two tar files, each containing a compiled package for a specific game version::

      swat-http.X.Y.Z.swat4.tar.gz
      swat-http.X.Y.Z.swat4exp.tar.gz

   with ``X.Y.Z`` being a package version, followed by a game version identifier::

      swat4 - SWAT 4 1.0-1.1
      swat4exp - SWAT 4: The Stetchkov Syndicate

   Please check the `releases page <https://github.com/sergeii/swat-http/releases>`_ to get the latest stable package version appropriate to your server game version.

2. Copy contents of a tar archive into the server's ``System`` directory.

3. Open ``Swat4DedicatedServer.ini``

4. Navigate to the ``[Engine.GameEngine]`` section.

5. Insert the following line below the `ServerActors=Utils.Package` line (assuming you have already installed the `Utils <https://github.com/sergeii/swat-utils>`_ package)::

    ServerActors=HTTP.Package

6. If you have done everything right, contents of your ``Swat4DedicatedServer.ini`` should look similar to::

    [Engine.GameEngine]
    EnableDevTools=False
    InitialMenuClass=SwatGui.SwatMainMenu
    ...
    ServerActors=Utils.Package
    ServerActors=HTTP.Package
    ...