swat-http
%%%%%%%%%

:Version:           1.2.0
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

Usage
=====

The library exposes the following public classes:

ClientOwner
^^^^^^^^^^^
``ClientOwner`` is an interface that your class must implement in order to access the Client API::

  public function OnRequestSuccess(int StatusCode, string Response, string Hostname, int Port)

::

  public function OnRequestFailure(eClientError ErrorCode, string ErrorMessage, string Hostname, int Port)


Client
^^^^^^
In order to interact with a remote HTTP service you must obtain an instance of the ``Client`` class::

  class MyClass extends Core.Object implements HTTP.ClientOwner;
  import enum eClientError from HTTP.Client;

  var HTTP.Client Client;

  function BeginPlay()
  {
    Super.BeginPlay();
    // Client is an Actor subclass hence the Spawn method
    self.Client = Spawn(class'HTTP.Client');
  }

  public function OnRequestSuccess(int StatusCode, string Response, string Hostname, int Port)
  {
    log(Hostname $ ":" $ Port $ " returned " $ StatusCode);
  }

  public function OnRequestFailure(eClientError ErrorCode, string ErrorMessage, string Hostname, int Port)
  {
    log(Hostname $ ":" $ Port $ " failed with code " $ GetEnum(eClientError, ErrorCode) $ " - " $ ErrorMessage);
  }

  event Destroyed()
  {
    if (self.Client != None)
    {
      self.Client.Destroy();
    }
    Super.Destroyed();
  }

``Send`` is the only ``Client`` method that is exposed to public::

  // Send an empty GET request
  Client.Send(Spawn('HTTP.Message'), "http://example.com/", 'GET', self)

Message
^^^^^^^
The ``Message`` class is an abstraction over HTTP request/response messaging. 

Note: Unlike request objects that you must create manually and pass it to a client, a response ``Message`` object is not a part of the public API.

Consider the following example::

  function SendRequest()
  {
    local HTTP.Message Request;

    Request = Spawn(class'HTTP.Message');

    // Fill a form
    Request.AddQueryString("title", "Django");
    Request.AddQueryString("text", "Django lets you build Web apps easily");
    // Use a cookie
    Request.AddHeader("Cookie", "sessionid=nrTaalka6Zb2zkhs");

    // Send a POST request
    // The request object will be automatically disposed
    self.Client.Send(Request, "http://example.com/", 'POST', self);
  }

If you need to send the same request to multiple sources then consider this example::

  function SendRequest()
  {
    local HTTP.Message Request;

    Request = Spawn(class'HTTP.Message');

    // Fill a form
    Request.AddQueryString("title", "Django");
    Request.AddQueryString("text", "Django lets you build Web apps easily");
    // Use a cookie
    Request.AddHeader("Cookie", "sessionid=nrTaalka6Zb2zkhs");

    // Obtain a copy of the Request object
    self.Client.Send(Request.Copy(), "http://example.com/", 'POST', self);
    // Another copy..
    self.Client.Send(Request.Copy(), "http://example.org/articles/", 'POST', self);

    // Dispose the template
    Request.Destroy();
  }

Utils
^^^^^
``Utils`` is a collection of helper static methods::

  bool ParseUrl(string Url, out string Hostname, out string Location, out optional int Port)
  string EncodeUrl(string String, optional string Safe)
  string EscapeHtml(string String)
  string EscapeHtml(string String)

Consider the following examples that exploit ``Utils``

* Parse url components::

    local string Url, Hostname, Location;

    Url = "http://example.com/articles/";

    if (class'HTTP.Utils'.static.ParseUrl(Url, Hostname, Location))
    {
      log("Parsed " $ Url);
      log("Hostname: " $ Hostname);
      log("Location: " $ Location);
    }
    else
    {
      log("Failed to parse " $ Url);
    }

* Percent-encode a string::

    local string Value, ValueEncoded;

    Value = "Hello!";
    ValueEncoded = class'HTTP.Utils'.static.EncodeUrl(Value);
    // ValueEncoded is Hello%21

* Escape html markup characters with the safe escape sequences::

    local string Value, ValueEncoded;

    Value = "<TAG>Player";
    ValueEncoded = class'HTTP.Utils'.static.EscapeHtml(Value);
    // ValueEncoded is &lt;TAG&gt;Player

* Unescape safe sequences::

    local string Value, ValueDecoded;

    Value = "&lt;TAG&gt;Player";
    ValueDecoded = class'HTTP.Utils'.static.UnescapeHtml(Value);
    // ValueDecoded is <TAG>Player
