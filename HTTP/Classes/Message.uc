class Message extends Engine.Actor;

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

const CRLF = "\r\n";

/**
 * An array of key=value paired headers 
 * @type array<string>
 * @example ["Content-Length", "148"]
 */
var protected array<string> Headers;

/**
 * An array of key=value paired querystring parameters
 * @type array<string>
 * @example ["username", "serge", "password", "secret"]
 */
var protected array<string> QueryString;

/**
 * HTTP message start line 
 * @type string
 * @example HTTP/1.1 200 OK
 * @example POST /document HTTP/1.1
 */
var protected string StartLine;

/**
 * HTTP status code (response)
 * @type int
 * @example 200
 */
var protected int Status;

/**
 * HTTP message body
 * @type string
 * @example <html><head><title>www.mytteam.com</title> <...>
 * @example username=serge&password=secret
 */
var protected string Body;

/**
 * Set a start line
 *
 * @param   string StartLine 
 *          A start line value (HTTP/1.1 200 OK, HTTP/1.1 404 NotFound, etc)
 * @return  void
 */
public function SetStartLine(string StartLine)
{
    self.StartLine = StartLine;
}

/**
 * Set response status code
 * 
 * @param   int Status
 * @return  void
 */
public function SetStatus(int Status)
{
    self.Status = Status;
}

/**
 * Add a new header key=value pair
 * 
 * @param   string Key
 * @param   string Value
 * @return  void
 */
public function AddHeader(coerce string Key, coerce string Value)
{
    self.Headers[self.Headers.Length] = Key;
    self.Headers[self.Headers.Length] = Value;
}

/**
 * Replace existing headers with a new array
 * 
 * @param   array<string> Headers
 *          An array of headers to be replaced with
 * @return  void
 */
public function SetHeaders(array<string> Headers)
{
    local int i;

    self.Headers.Remove(0, self.Headers.Length);
    // Copy elements
    for (i = 0; i < Headers.Length; i++)
    {
        self.Headers[self.Headers.Length] = Headers[i];
    }
}

/**
 * Set or replace the HTTP message body with provided value
 * 
 * @param   string Body
 * @return  void
 */
public function SetBody(coerce string Body)
{
    self.Body = "";
    self.AppendToBody(Body);
}

/**
 * Append a chunk of data to the message body
 * 
 * @param   string String
 *          A chunk of data
 * @return  void
 */
public function AppendToBody(coerce string String)
{
    self.Body = self.Body $ String;
}

/**
 * Add a new query string key=value pair
 * 
 * @param   Key
 * @param   Value
 * @return  void
 */
public function AddQueryString(coerce string Key, coerce string Value)
{
    self.QueryString[self.QueryString.Length] = Key;
    self.QueryString[self.QueryString.Length] = Value;
}

/**
 * Set or replace the existing query string array with the provided value
 * 
 * @param   array<string>
 *          An array of HTTPQuery key=value pairs to be replaced with
 * @return  void
 */
public function SetQueryString(array<string> QueryString)
{
    local int i;

    self.QueryString.Remove(0, self.QueryString.Length);
    // Copy elements
    for (i = 0; i < QueryString.Length; i++)
    {
        self.QueryString[self.QueryString.Length] = QueryString[i];
    }
}

/**
 * Return the start line value
 * 
 * @return  string
 */
public function string GetStartLine()
{
    return self.StartLine;
}

/**
 * Return status code
 * 
 * @return  int
 */
public function int GetStatus()
{
    return self.Status;
}

/**
 * Return a header value with the first matching key
 * 
 * @param   string Key
 * @return  string
 */
public function string GetHeader(string Key)
{
    local int i;

    for (i = 0; i < self.Headers.Length; i += 2)
    {
        if (self.Headers[i] ~= Key)
        {
            return self.Headers[i+1];
        }
    }
    return "";
}

/**
 * Return the array of headers
 * 
 * @return  array<string>
 */
public function array<string> GetHeaders()
{
    return self.Headers;
}

/**
 * Return headers in a form suitable for HTTP communication (i.e. delimited by CRLF)
 * 
 * @return  string
 */
public function string AssembleHeaders()
{
    local int i;
    local array<string> Array;

    for (i = 0; i < self.Headers.Length; i += 2)
    {
        Array[Array.Length] = self.Headers[i] $ ": " $ self.Headers[i+1];
    }
    return class'Utils.ArrayUtils'.static.Join(Array, class'Message'.const.CRLF);
}

/**
 * Return the body
 * 
 * @return  string
 */
public function string GetBody()
{
    return self.Body;
}

/**
 * Return the QueryString array
 * 
 * @return  array<string>
 */
public function array<string> GetQueryString()
{
    return self.QueryString;
}

/**
 * Return the QueryString array with its key-pair values joined together
 *
 * @return  string
 */
public function string AssembleQueryString()
{
    local int i;
    local array<string> Array;
    local string Key, Value;

    for (i = 0; i < self.QueryString.Length; i += 2)
    {
        Key = class'HTTP.Utils'.static.EncodeUrl(self.QueryString[i]);
        Value = class'HTTP.Utils'.static.EncodeUrl(self.QueryString[i+1]);
        Array[Array.Length] = Key $ "=" $ Value;
    }

    return class'Utils.ArrayUtils'.static.Join(Array, "&");
}

/**
 * Return a copy of the instance
 * 
 * @return  class'Message'
 */
public function Message Copy()
{
    local Message Instance;

    Instance = Spawn(class'HTTP.Message');

    Instance.SetStartLine(self.StartLine);
    Instance.SetBody(self.Body);
    Instance.SetHeaders(self.Headers);
    Instance.SetQueryString(self.QueryString);

    return Instance;
}

event Destroyed()
{
    log(self $ " is about to be destroyed");

    self.Headers.Remove(0, self.Headers.Length);
    self.QueryString.Remove(0, self.QueryString.Length);
    self.StartLine = "";
    self.Body = "";

    Super.Destroyed();
}

/* vim: set ft=java: */