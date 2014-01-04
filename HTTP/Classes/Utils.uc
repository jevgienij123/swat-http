class Utils extends Core.Object;

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

/**
 * List of entity characters (", >, etc)
 * @type string
 */
var protected array<string> EntityChars;

/**
 * List of corresponding entity named references (&quot;, &gt;, etc)
 * @type string
 */
var protected array<string> EntityDefs;

/**
 * Attempt to parse url matching the following pattern: http://hostname[:port][/location]
 *
 * If successful, return true and provide the Hostname, Location 
 * and optionally Port passed-by-reference arguments with relevant data
 * 
 * @param   string Url
 * @param   string Hostname (out)
 * @param   string Location (out)
 * @param   int Port (out, optional)
 * @return  bool
 */
static function bool ParseUrl(string Url, out string Hostname, out string Location, out optional int Port)
{
    local array<string> HostAddrSplit;
    local string HostAddr;
    local int n;

    // http://www.example.com:8000/document -> www.example.com:8000/document
    if (Left(Url, 7) == "http://")
    {
        Url = Mid(Url, 7);
    }
    else
    {
        return false;
    }
    // The first leading slash character separates hostname[:port] from location
    n = InStr(Url, "/");
    // If not found, assume host address to take up to the whole string
    if (n == -1)
    {
        n = Len(Url);
    }
    // So a www.example.com:8000/document 
    // would be split to www.example.com:8000 and /document
    HostAddr = Left(Url, n);
    Location = Mid(Url, n);
    // Separate hostname from port
    HostAddrSplit = class'StringUtils'.static.Part(HostAddr, ":");
    // www.example.com:8000 -> www.example.com + 8000
    switch (HostAddrSplit.Length)
    {
        case 2:
            Port = int(HostAddrSplit[1]);
            // no break
        case 1:
            Hostname = HostAddrSplit[0];
            break;
        default:
            return false;
    }
    return true;
}

/**
 * Percent-encode a string
 *
 * http://www.ietf.org/rfc/rfc3986.txt (2.1. Percent-Encoding)
 * 
 * @param   string Str
 *          url-unsafe string
 * @param   string Safe (optional)
 *          Optional list of characters that should not be escaped
 * @return  string
 */
static function string EncodeUrl(string String, optional string Safe)
{
    local int i;
    local string Char;
    local array<byte> Bytes;
    local string Result;

    // Encode a literal %
    String = class'Utils.StringUtils'.static.Replace(String, "%", "%25");
    // Encode the string into a utf-8 byte array
    Bytes = class'Utils.UnicodeUtils'.static.ToUTF8(String);
    // Then decide whether bytes from the array should be percent-encoded
    // or mapped to their respective ASCII characters
    for (i = 0; i < Bytes.Length; i++)
    {
        // Escape a byte if its corresponding ascii character
        // is not from the set of [a-zA-Z0-9~_%.-]
        if (!(
            (Bytes[i] >= 48 && Bytes[i] <= 57)      // [0-9]
         || (Bytes[i] >= 65 && Bytes[i] <= 90)      // [A-Z]
         || (Bytes[i] >= 97 && Bytes[i] <= 122)     // [a-z]
         || (Bytes[i] >= 45 && Bytes[i] <= 46)      // [.-]
         || Bytes[i] == 126                         // [~]
         || Bytes[i] == 95                          // [_]
         || Bytes[i] == 37                          // [%]
         || (Safe != "" && InStr(Safe, Chr(Bytes[i])) >= 0)
        ))
        {
            Char = "%" $ class'Utils.StringUtils'.static.Rjust(class'Utils.IntUtils'.static.ToString(Bytes[i], 16), 2, "0");
        }
        // Otherwise leave as is
        else
        {
            Char = Chr(Bytes[i]);
        }
        Result = Result $ Char;
    }
    return Result;
}

/**
 * Replace the characters &, <, >, " with HTML-safe sequences.
 * 
 * @param   string String
 * @return  string
 */
static function string EscapeHtml(string String)
{
    local int i;

    for (i = 0; i < class'Utils'.default.EntityChars.Length; i++)
    {
        String = class'Utils.StringUtils'.static.Replace(
            String, class'Utils'.default.EntityChars[i], class'Utils'.default.EntityDefs[i]
        );
    }
    return String;
}

/**
 * Replace HTML-safe sequences with their corresponding characters
 * 
 * @param   string String
 * @return  string
 */
static function string UnescapeHtml(string String)
{
    local int i;

    // Do replacement in reversed order, so &amp; get's unescaped last
    for (i = class'Utils'.default.EntityChars.Length-1; i >= 0 ; i--)
    {
        String = class'Utils.StringUtils'.static.Replace(
            String,
            class'Utils'.default.EntityDefs[i],
            class'Utils'.default.EntityChars[i]
        );
    }
    return String;
}

defaultproperties
{
    EntityChars(0)="&";
    EntityChars(1)="<";
    EntityChars(2)=">";
    EntityChars(3)="\\"";

    EntityDefs(0)="&amp;";
    EntityDefs(1)="&lt;";
    EntityDefs(2)="&gt;";
    EntityDefs(3)="&quot;"
}

/* vim: set ft=java: */