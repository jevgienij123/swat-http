class Request extends Engine.Actor
  dependson(Link)
  dependson(Client);

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

import enum eLinkError from Link;
import enum eClientError from Client;

/**
 * Time a Request instance should be destroyed if not interacted with
 * @type float
 */
const DESTRUCTION_TIME = 30.0;

/**
 * Message request instance
 * @type class'Message'
 */
var protected Message Request;

/** 
 * Message response instance
 * @type class'Message'
 */
var protected Message Response;

/**
 * Request owner instance
 * @type interface'ClientOwner'
 */
var protected ClientOwner Owner;

/**
 * Assigned hostname/ip address
 * @type string
 */
var protected string Hostname;

/**
 * Assigned port number
 * @type int
 */
var protected int Port;

/**
 * HTTP method
 * @type name
 */
var protected name Method;

/**
 * Attempt count
 * @type int
 */
var protected int Attempts;

/**
 * Attempt limit
 * @type int
 */
var protected int MaxAttempts;

/**
 * Since no other instance holds a reference to Request objects,
 * a precaution measure like this helps to avoid memory leaks
 * @type float
 */
var protected float DestructionTimer;

/**
 * Attach a method to this delegate 
 * in order to receieve a call on a request success
 * 
 * @param   class'Request' Request
 *          Request instance
 * @param   class'Link' Link
 *          Assotiated link instance
 * @return  void
 */
delegate OnRequestSuccess(Request Request, Link Link);

/**
 * Call this delegate on a request/response failure
 * 
 * @param   class'Request' Request
 *          Instance of the failed request
 * @param   class'Link' Link
 *          Assotiated link instance
 * @param   enum'eClientError' Error
 *          Error code
 * @param   string ErrorMessage (optional)
 *          Optional error message
 * @return  void
 */
delegate OnRequestFailure(Request Request, Link Link, eClientError Error, optional string ErrorMessage);

/**
 * Warning: Self destruct sequence has been initiated.
 * 
 * @return  void
 */
public function PreBeginPlay()
{
    Super.PreBeginPlay();
    self.DestructionTimer = class'Request'.const.DESTRUCTION_TIME;
}

/**
 * Count time untill self destruction
 * 
 * @param   float Delta
 * @return  void
 */
public function Tick(float Delta)
{
    if (self.DestructionTimer <= 0)
    {
        self.Destroy();
    }
    self.DestructionTimer -= Delta;
}

/**
 * Attempt to parse headers and body on every subsequent delegate call
 * 
 * @param   class'Link' Link
 *          Reference to the transmitting link instance
 * @param   string Data
 *          Plain text data
 * @return  void
 */
public function HandleDataReceived(Link Link, string Data)
{
    local int StatusCode;
    local string StartLine, Body;
    local array<string> Headers;

    if (Data == "" || self.Response == None)
    {
        return;
    }
    // Headers have already been set, this must be a portion of body
    if (self.Response.GetStatus() > 0)
    {
        self.Response.AppendToBody(Data);
    }
    // If not, attempt to parse them
    else
    {
        Headers = self.ParseResponseHeaders(Data, StatusCode, StartLine, Body);
        // Invalid headers - abort
        if (Headers.Length == 0)
        {
            self.OnRequestFailure(
                self, Link, CE_RESPONSE_CONTENTS, "Unable to parse received data (no headers) \"" $ Left(Data, 20) $ "\""
            );
            return;
        }
        self.Response.SetStartLine(StartLine);
        self.Response.SetStatus(StatusCode);
        self.Response.SetHeaders(Headers);
        self.Response.SetBody(Body);
    }
    if (self.CheckResponseBody())
    {
        self.OnRequestSuccess(self, Link);
    }
}

/**
 * Assemble and send http request message upon link readiness
 * 
 * @param   class'Link' Link
 * @return  void
 */
public function HandleLinkReady(Link Link)
{
    self.Response = new class'Message';
    Link.SendText(class'HTTP.Request'.static.AssembleMessage(self.Request));
}

/**
 * Trigger request failure upon link closing
 * 
 * @param   class'Link' Link
 * @return  void
 */
public function HandleLinkClosed(Link Link)
{
    self.OnRequestFailure(self, Link, CE_LINK_FAILURE, "connection closed");
}

/**
 * Trigger request failure upon connection failure
 * 
 * @param   class'Link' Link
 * @param   enum'eLinkError' ErrorCode
 * @param   string ErrorMessage
 * @return  void
 */
public function HandleLinkFailure(Link Link, eLinkError ErrorCode, string ErrorMessage)
{
    self.OnRequestFailure(self, Link, CE_LINK_FAILURE, ErrorMessage $ " (" $ GetEnum(eLinkError, ErrorCode) $ ")");
}

/**
 * Attempt to parse http headers (and optionally body) from the given string
 * 
 * @param   Data
 *          Subject of parsing
 * @param   int StatusCode (out)
 *          Response status code (e.g 200)
 * @param   string StartLine (out)
 *          Response start line (e.g. HTTP/1.1 200 OK)
 * @param   string Body (out)
 *          Parsed response body (or piece of)
 * @return  array<string>
 */
protected function array<string> ParseResponseHeaders(string Data, out int StatusCode, out string StartLine, out string Body)
{
    local string StatusString;
    local int i;
    local array<string> Lines, HeaderSplit, Headers;
    local bool bError;

    // Split string with \r\n
    Lines = class'Utils.StringUtils'.static.Part(Data, class'Message'.const.CRLF);

    for (i = 0; i < Lines.Length; i++)
    {
        // Start line
        if (i == 0)
        {
            // Parse the status code HTTP/1.1 [200] OK, HTTP/1.1 [404] Not Found, HTTP/1.1 [403] Forbidden, etc
            StatusString = Mid(Lines[0], 9, 3);
            // Check if the parsed value is numeric
            if (!class'Utils.StringUtils'.static.IsDigit(StatusString))
            {
                bError = true;
                break;
            }
            StatusCode = int(StatusString);
            StartLine = Lines[0];
        }
        // If encountered an empty line, then that must be the line between \r\n..\r\n
        // The next line begins with the message body
        else if (Lines[i] == "")
        {
            Lines.Remove(0, i+1);
            Body = class'Utils.ArrayUtils'.static.Join(Lines, class'Message'.const.CRLF);
            break;
        }
        // Parse headers
        else
        {
            // Separate key from value
            HeaderSplit = class'Utils.StringUtils'.static.Part(Lines[i], ": ");

            if (HeaderSplit.Length != 2)
            {
                break;
                bError = true;
            }

            Headers[Headers.Length] = HeaderSplit[0];
            Headers[Headers.Length] = HeaderSplit[1];
        }
    }

    if (bError)
    {
        Headers.Remove(0, Headers.Length);
        // Discard any changes done to the out args
        StatusCode = 0;
        Body = "";
    }

    return Headers;
}

/**
 * Tell whether the response has been completely assembled
 * 
 * @return  bool
 */
protected function bool CheckResponseBody()
{
    if (self.Method != 'HEAD')
    {
        // Chunked body
        if (self.Response.GetHeader("Transfer-Encoding") ~= "chunked")
        {
            if (self.NormalizeResponseBody())
            {
                return true;
            }
            return false;
        }
        // Explicit content length
        else if (class'Utils.StringUtils'.static.IsDigit(self.Response.GetHeader("Content-Length")))
        {
            if (int(self.Response.GetHeader("Content-Length")) == Len(self.Response.GetBody()))
            {
                return true;
            }
            return false;
        }
        else
        {
            // Leave body as is
            return true;
        }
    }
    // HEAD request - no body expected
    self.Response.SetBody("");
    return true;
}

/**
 * Attempt to normalize a chunked response body
 * 
 * @return  bool
 */
protected function bool NormalizeResponseBody()
{
    local int ChunkSize;
    local string ChunkedBody, NormalizedBody, Chunk;

    ChunkedBody = self.Response.GetBody();

    while (ChunkedBody != "")
    {
        if (!self.ParseChunk(ChunkedBody, Chunk, ChunkSize))
        {
            return false;
        }
        else
        {
            // End of chunked body
            if (ChunkSize == 0)
            {
                // Replace the chunked body
                self.Response.SetBody(NormalizedBody);
                return true;
            }
            NormalizedBody = NormalizedBody $ Chunk;
        }
    }
    return false;
}

/**
 * Attempt to parse a piece of chunked body
 * 
 * @param   string Body (out)
 *          Chunked body
 * @param   string Chunk (out)
 *          Parsed chunk
 * @param   int ChunkSize (out)
 *          Size of the parsed chunk
 * @return  bool
 */
protected function bool ParseChunk(out string Body, out string Chunk, out int ChunkSize)
{
    local int CrlfPos;
    local array<string> ChunkHeader;

    ChunkSize = 0;

    CrlfPos = InStr(Body, class'HTTP.Message'.const.CRLF);
    // Parse header of the nearest chunk
    if (CrlfPos > 0)
    {
        ChunkHeader = class'Utils.StringUtils'.static.Part(Left(Body, CrlfPos), ";");
        // Parse the chunk size
        ChunkSize = class'Utils.IntUtils'.static.ToInt(ChunkHeader[0], 16);
        // Grab as many data as it has been declared in the header
        if (ChunkSize > 0)
        {
            Chunk = Mid(Body, CrlfPos + 2, ChunkSize);
            // Check the actual length
            if (Len(Chunk) == ChunkSize)
            {
                // Remove the parsed chunk from the original chunked body
                Body = Right(Body, Len(Body) - (CrlfPos + ChunkSize + 4));
                return true;
            }
        }
        // End of chunked body
        else if (ChunkHeader[0] == "0")
        {
            Body = "";
            return true;
        }
    }
    return false;
}

/**
 * Set the request owner
 * 
 * @param   interface'ClientOwner' Owner
 * @return  void
 */
public function SetRequestOwner(ClientOwner Owner)
{
    self.Owner = Owner;
}

/**
 * Return the request owner
 * 
 * @return  interface'ClientOwner'
 */
public function ClientOwner GetRequestOwner()
{
    return self.Owner;
}

/**
 * Set request message
 * 
 * @param   class'Message' Message
 * @return  void
 */
public function SetRequestMessage(Message Message)
{
    self.Request = Message;
}

/**
 * Return the request message instance
 * 
 * @return  class'Message'
 */
public function Message GetRequestMessage()
{
    return self.Request;
}

/**
 * Return response message instance
 * 
 * @return  class'Message'
 */
public function Message GetResponseMessage()
{
    return self.Response;
}

/**
 * Set request method
 * 
 * @param   name Method
 * @return  void
 */
public function SetMethod(name Method)
{
    self.Method = Method;
}

/**
 * Return initial request method
 * 
 * @return  name
 */
public function name GetMethod()
{
    return self.Method;
}

/**
 * Set host name/ip
 * 
 * @param   string Hostname
 * @return  void
 */
public function SetHostname(string Hostname)
{
    self.Hostname = Hostname;
}

/**
 * Set host port
 * 
 * @param   int Port
 * @return  void
 */
public function SetPort(int Port)
{
    self.Port = Port;
}

/**
 * Set remote host name/ip and port
 * 
 * @param   string Hostname
 * @param   int Port
 * @return  void
 */
public function SetAddr(string Hostname, int Port)
{
    self.SetHostname(Hostname);
    self.SetPort(Port);
}

/**
 * Return host name/ip
 * 
 * @return string
 */
public function string GetHostname()
{
    return self.Hostname;
}

/**
 * Return host port number
 * 
 * @return  int
 */
public function int GetPort()
{
    return self.Port;
}

/**
 * Increment attempt count by one
 * 
 * @return  void
 */
public function IncrementAttempts()
{
    // Update destruction timer
    self.DestructionTimer = class'Request'.const.DESTRUCTION_TIME;
    self.Attempts++;
}

/**
 * Return current attempt count
 * 
 * @return  int
 */
public function int GetAttempts()
{
    return self.Attempts;
}

/**
 * Set attempt limit
 * 
 * @param   int MaxAttempts
 * @return  void
 */
public function SetMaxAttempts(int MaxAttempts)
{
    self.MaxAttempts = MaxAttempts;
}

/**
 * Return value of the attempt limit
 * 
 * @return  int
 */
public function int GetMaxAttempts()
{
    return self.MaxAttempts;
}

/**
 * Assemble a http message string
 * 
 * @param   class'Message' Message
 * @return  string
 */
static function string AssembleMessage(Message Message)
{
    return (
           Message.GetStartLine() 
         $ class'Message'.const.CRLF
         $ Message.AssembleHeaders() 
         $ class'Message'.const.CRLF
         $ class'Message'.const.CRLF
         $ Message.GetBody()
    );
}

event Destroyed()
{
    if (self.Request != None)
    {
        self.Request.Destroy();
        self.Request = None;
    }
    if (self.Response != None)
    {
        self.Response.Destroy();
        self.Response = None;
    }
    self.Owner = None;
    self.OnRequestSuccess = None;
    self.OnRequestFailure = None;

    log(self $ " is about to be destroyed");

    Super.Destroyed();
}

/* vim: set ft=java: */