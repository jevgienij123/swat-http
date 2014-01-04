class Client extends Engine.Actor;

/**
 * Copyright (c) 2014 Sergei Khoroshilov <kh.sergei@gmail.com>
 * 
 * Permission is hereby granted, free of charge, to any person obtaining a copy
 * of this software and associated documentation files (the "Software"), to deal
 * in the Software without restriction, including without limitation the rights
 * to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
 * copies of the Software, and to permit persons to whom the Software is
 * furnished to do so, subject to the following conditions:
 * 
 * The above copyright notice and this permission notice shall be included in
 * all copies or substantial portions of the Software.
 * 
 * THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
 * IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
 * FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
 * AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
 * LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
 * OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
 * THE SOFTWARE.
 */

enum eClientError
{
    CE_BAD_URL,             /* An error caused by supplying an invalid url to client */
    CE_BAD_METHOD,          /* Unsupported method (i.e. other that GET, POST, HEAD) */
    CE_LINK_FAILURE,        /* An error caused by a connection failure */
    CE_RESPONSE_CONTENTS,   /* An error occurred during response buffering and/or parsing */
};

struct sDomainCacheEntry
{
    /**
     * Resolved hostname
     * @type string
     */
    var string Hostname;

    /**
     * An IP address the assotiated hostname has been resolved to
     * @type string
     */
    var string IpAddr;
};

/**
 * List of cached IP addresses
 * @type array<struct'sDomainCacheEntry'>
 */
var protected array<sDomainCacheEntry> DomainCache;

/**
 * List of active links
 * @type array<class'Link'>
 */
var protected array<Link> Links;

/**
 * Send a HTTP request
 *  
 * @param   class'Message' Message
 *          HTTP request message
 * @param   string URL
 *          http://example.com/script.cgi
 * @param   name Method
 *          HTTP method (GET, POST)
 * @param   interface'ClientOwner' Owner
 *          A ClientOwner instance that should a tied with the new request
 * @param   int Attempts
 *          Times this request will be allowed to requeued in case of a failure
 * @return  void
 */
public function Send(Message Message, string URL, name Method, ClientOwner Owner, optional int Attempts)
{
    local Request Request;
    local string Hostname, Location, QueryString;
    local int Port;

    // Attempt to parse url
    if (!class'HTTP.Utils'.static.ParseUrl(URL, Hostname, Location, Port))
    {
        Owner.OnRequestFailure(CE_BAD_URL, Url $ " is not a valid url", "", 0);
        return;
    }
    // Set default http port
    if (Port == 0)
    {
        Port = 80;
    }
    // Dont url-encode leading slashes in location
    Location = class'HTTP.Utils'.static.EncodeUrl(Location, "/");
    // key1=value2&key2=value query string (url-safe)
    QueryString = Message.AssembleQueryString();
    // Headers
    Message.AddHeader("User-Agent", "SWAT-HTTP/" $ class'Package'.const.VERSION);
    Message.AddHeader("Accept", "*/*");
    Message.AddHeader("Host", Hostname);
    Message.AddHeader("Connection", "Keep-Alive");
    // Set method specific headers
    switch (Method)
    {
        case 'POST' :
            // Set POST headers
            Message.AddHeader("Content-Type", "application/x-www-form-urlencoded");
            Message.AddHeader("Content-Length", Len(QueryString));
            // query string becomes the message body
            Message.SetBody(QueryString);
            break;
        case 'GET' :
        case 'HEAD' :
            // in case of GET/HEAD, append query string to location
            if (QueryString != "")
            {
                // Check if there's already a question mark in location
                if (InStr(Location, "?") != -1)
                {
                    // If its the last character, ignore it
                    if (Right(Location, 1) != "?")
                    {
                        // If not, then append this qs to the existing query string
                        Location = Location $ "&";
                    }
                }
                else
                {
                    Location = Location $ "?";
                }
                Location = Location $ QueryString;
            }
            break;
        default: 
            // Only POST and GET/HEAD are currently supported
            Owner.OnRequestFailure(CE_BAD_METHOD, "HTTP Method " $ Caps(string(Method)) $ " is not supported", "", 0);
            return;
    }
    // ie POST /script.cgi HTTP/1.1
    Message.SetStartLine(Caps(string(Method)) $ " " $ Location $ " HTTP/1.1");

    Request = self.CreateRequest();
    Request.SetRequestOwner(Owner);
    Request.SetMaxAttempts(Max(1, Attempts));
    Request.SetMethod(Method);
    Request.SetAddr(Hostname, Port);
    Request.SetRequestMessage(Message);
    // Queue up
    self.QueueRequest(Request);
}

/**
 * Spawn a new request instancde
 * 
 * @return  class'Request'
 */
protected function Request CreateRequest()
{
    local Request Instance;

    Instance = Spawn(class'HTTP.Request');

    Instance.OnRequestFailure = self.HandleRequestFailure;
    Instance.OnRequestSuccess = self.HandleRequestSuccess;

    return Instance;
}

/**
 * Queue a request by assigning an available link
 * to provided instance and incrementing its attempt count
 * 
 * @param   class'Request' Request
 * @return  void
 */
protected function QueueRequest(Request Request)
{
    local Link Link;
    // Increment attempt count
    Request.IncrementAttempts();
    // Aquire a host/port appropriate tcp link
    Link = self.GetLink(Request.GetHostname(), Request.GetPort());
    Link.OnLinkReady = Request.HandleLinkReady;
    Link.OnDataReceived = Request.HandleDataReceived;
    Link.OnLinkClosed = Request.HandleLinkClosed;
    Link.OnLinkFailure = Request.HandleLinkFailure;
    // If the link has already been in use, 
    // it wont call its OnLinkReady delegate ever again..
    // ..unless we ask nicely :-)
    Link.Knock();
}

/**
 * Aquire an idling link appropriate to given Hostname and Port
 * If none found, create and return a new Link instance
 *
 * @param   string Hostname
 * @param   int Port
 * @return  class'Link'
 */
protected function Link GetLink(string Hostname, int Port)
{
    local int i;

    for (i = 0; i < self.Links.Length; i++)
    {
        // If a link has been assigned with a previously resolved IP address
        if (self.Links[i].GetHostname() ~= Hostname &&  self.Links[i].GetPort() == Port)
        {
            if (self.Links[i].GetState() == STATE_IDLING)
            {
                return self.Links[i];
            }
        }
    }
    return self.CreateLink(Hostname, Port);
}

/**
 * Create and return a new Link instance appropriate to the given address
 * 
 * @param   string Hostname
 *          Host name
 * @param   int Port
 *          Destination port
 * @return  class'Link'
 */
protected function Link CreateLink(string Hostname, int Port)
{
    local string IpAddr;
    local Link Link;

    Link = Spawn(class'HTTP.Link');

    Link.SetHostname(Hostname);
    Link.SetPort(Port);
    // Attempt to retrieve cached IP
    if (self.ResolveHostname(Hostname, IpAddr))
    {
        Link.SetIp(IpAddr);
    }
    Link.OnLinkDestroyed = self.HandleLinkDestroyed;
    // Allow clients to cache resolved hostnames
    Link.OnHostnameResolved = self.HandleHostnameResolved;

    Link.Init();
    // Store the instance, so that other requests could utilize it as well
    self.Links[self.Links.Length] = Link;

    return Link;
}

/**
 * Attempt to resolve given hostname against the list of previously resolved hostnames.
 * If lookup succeeded, return true.
 * 
 * @param   string Hostname
 * @param   string IpAddr (out)
 * @return  bool
 */
protected function bool ResolveHostname(string Hostname, out string IpAddr)
{
    local int i;

    for (i = 0; i < self.DomainCache.Length; i++)
    {
        if (self.DomainCache[i].Hostname ~= Hostname)
        {
            IpAddr = self.DomainCache[i].IpAddr;
            return true;
        }
    }
    return false;
}

/**
 * Propagate response data to the original request owner
 * Also decide whether the assotiated link should be kept alive or destroyed
 *
 * @param   class'Request' Request
 *          Succeeded request
 * @param   class'Link' Link
 *          Assotiated link instance
 * @return  void
 */
public function HandleRequestSuccess(Request Request, Link Link)
{
    // Clear the delegates
    Link.OnLinkReady = None;
    Link.OnDataReceived = None;
    Link.OnLinkClosed = None;
    Link.OnLinkFailure = None;
    // If the http server hasnt provided a valid Keep-Alive header,
    // assume it will close the connection shortly
    if (!(Request.GetResponseMessage().GetHeader("Connection") ~= "Keep-Alive"))
    {
        Link.Quit();
    }
    // otherwise free the link for further use
    else
    {
        Link.Free();
    }
    // Pass response data to the owner
    Request.GetRequestOwner().OnRequestSuccess(
        Request.GetResponseMessage().GetStatus(), 
        class'Utils'.static.UnescapeHTML(
            class'Utils.UnicodeUtils'.static.DecodeUTF8(Request.GetResponseMessage().GetBody())
        ),
        Link.GetHostname(),
        Link.GetPort()
    );
    // Also destroy the instance upon succesful delegation
    Request.Destroy();
}

/**
 * Decide whether failed request should be requeued or dropped at all
 *
 * @param   class'Request' Request
 *          Instance of the failed request
 * @param   class'Link' Link
 *          Assotiated link instance
 * @param   enum'eClientError' Error
 *          Error code
 * @param   string Message (optional)
 *          Optional error message
 * @return  void
 */
public function HandleRequestFailure(Request Request, Link Link, eClientError ErrorCode, optional string ErrorMessage)
{
    if (Request.GetAttempts() >= Request.GetMaxAttempts())
    {
        Request.GetRequestOwner().OnRequestFailure(
            ErrorCode, 
            ErrorMessage,
            Link.GetHostname(),
            Link.GetPort()
        );
        Request.Destroy();
        return;
    }
    // Requeue failed request
    self.QueueRequest(Request);
}

/**
 * Store a resolved Hostname:IP pair whenever the former gets resolved 
 * 
 * @param   class'Link' Link
 *          A Link instance that has the job resolving this hostname
 * @param   string Hostname
 *          The hostname that has been resolved
 * @param   IpAddr
 *          An IP address that the hostname has been resolved to
 * @return  void
 */
public function HandleHostnameResolved(Link Link, string Hostname, string IpAddr)
{
    local int i;
    local sDomainCacheEntry NewEntry;

    for (i = 0; i < self.DomainCache.Length; i++)
    {
        if (self.DomainCache[i].Hostname ~= Hostname)
        {
            // This hostname has already been cached
            return;
        }
    }
    // Set up a new entry
    NewEntry.Hostname = Hostname;
    NewEntry.IpAddr = IpAddr;
    // Cache it
    self.DomainCache[self.DomainCache.Length] = NewEntry;
}

/**
 * Attempt to remove link instance from the link list
 * whenever the former is about to be destroyed
 * 
 * @param   class'Link' Link
 *          Link instance that is about to be destroyed
 * @return  void
 */
public function HandleLinkDestroyed(Link Link)
{
    local int i;

    for (i = self.Links.Length-1; i >= 0; i--)
    {
        if (self.Links[i] == Link)
        {
            self.Links[i] = None;
            self.Links.Remove(i, 1);
            return;
        }
    }
}

event Destroyed()
{
    while (self.Links.Length > 0)
    {
        if (self.Links[0] != None)
        {
            self.Links[0].OnLinkDestroyed = None;
            self.Links[0].Destroy();
        }
        self.Links.Remove(0, 1);
    }

    log(self $ " has been destroyed");

    Super.Destroyed();
}

/* vim: set ft=java: */