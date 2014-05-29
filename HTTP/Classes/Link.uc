class Link extends IPDrv.TcpLink;

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
 * Size of a request buffer
 * @type int
 */
const BUFFER_SIZE=10000;

/**
 * Make sure response length is no greater than this value (in bytes)
 * Drop link in case of length excess
 * @type int
 */
const MAX_RESPONSE_LENGTH=4096;

enum eState
{
    STATE_NONE,         /* Non-valid state */
    STATE_RESOLVING,    /* Resolving hostname */
    STATE_OPENING,      /* Opening connection */
    STATE_IDLING,       /* Waiting for a request */
    STATE_READING,      /* Writing/Reading into a socket */
    STATE_FREEING,      /* Freeing a no longer used link */
    STATE_CLOSING,      /* Closing connection */
};

enum eLinkError
{
    LE_RESOLVE,         /* Hostname resolve error */
    LE_TIMEOUT,         /* Stage timeout error */
    LE_LENGTH,          /* Request/response length limit excess */
};

/**
 * IP address of the remote host (optional)
 * @type string
 */
var protected string Ip;

/**
 * Hostname of the remote host
 * @type string
 */
var protected string Hostname;

/**
 * Destination port
 * @type int
 */
var protected int Port;

/**
 * Current link state
 * @type enum'eState'
 */
var protected eState State;

/**
 * DNS hostname resolving timeout
 * @type float
 */
var config float TimeoutResolve;

/**
 * Connection opening timeout
 * @type float
 */
var config float TimeoutOpen;

/**
 * Stream reading timeout
 * @type float
 */
var config float TimeoutRead;

/**
 * Connection idling timeout
 * @type float
 */
var config float TimeoutIdle;

/**
 * Time required to free a link
 * @type float
 */
var protected float TimeoutFree;

/**
 * Connection closing timeout
 * @type float
 */
var protected float TimeoutClose;

/**
 * Time untill a state timeout
 * @type float
 */
var protected float Countdown;

/**
 * Current response length
 * @type int
 */
var protected int ResponseLength;

/**
 * Call this delegate whenever hostname is resolved to an IP address
 * 
 * @param   class'Link' Link
 *          Reference to the instance
 * @param   string Hostname
 *          Resolved hostname
 * @param   string IP
 *          IP address the hostname has been resolved to
 * @return  void
 */
delegate OnHostnameResolved(Link Link, string Hostname, string IP);

/**
 * Call this delegate whenever connection gets either open or freed
 * 
 * @param   class'Link' Link
 * @return  void
 */
delegate OnLinkReady(Link Link);

/**
 * Call this delegate whenever connection gets closed
 * 
 * @param   class'Link' Link
 * @return  void
 */
delegate OnLinkClosed(Link Link);

/**
 * Call this delegate whenever data is received
 * 
 * @param   class'Link' Link
 * @param   string Data
 * @return  void
 */
delegate OnDataReceived(Link Link, string Data);

/**
 * Call this delegate whenever a link failure is encountered
 * 
 * @param   class'Link' Link
 *          Reference to current instance
 * @param   enum'eLinkError' Error
 *          Error code
 * @param   string ErrorMessage
 *          Optional error message
 * @return  void
 */
delegate OnLinkFailure(Link Link, eLinkError Error, string ErrorMessage);

/**
 * Call this delegate whenever a link object is destroyed
 * 
 * @param   class'Link' Link
 * @return  void
 */
delegate OnLinkDestroyed(Link Link);

/**
 * Check wether a link state has timed out
 *
 * @param   float Delta
 *          Tick rate
 * @return  void
 */
public function Tick(float Delta)
{
    // Keep deducting time
    if (self.Countdown > 0)
    {
        self.Countdown -= Delta;
        return;
    }
    switch (self.State)
    {
        case STATE_FREEING:
            self.TriggerLinkReady();
            return;
        case STATE_CLOSING:
            log(self $ " failed to close connection in time");
            self.TriggerLinkClosed();
            return;
        case STATE_RESOLVING:
        case STATE_OPENING:
        case STATE_READING:
        case STATE_IDLING:
            break;
        default:
            return;
    }
    // Trigger a timeout error
    self.TriggerLinkFailure(LE_TIMEOUT, string(GetEnum(eState, self.State)) $ " timed out");
}

/**
 * Attempt to open a connection upon a successful hostname resolve
 * 
 * @param   struct'IpAddr' Addr
 *          Resolved IP address
 * @return  void
 */
event Resolved(IpAddr Addr)
{
    if (self.Ip == "")
    {
        self.Ip = class'StringUtils'.static.ParseIP(IpAddrToString(Addr));
        self.OnHostnameResolved(self, self.Hostname, self.Ip);
        log(self $ " resolved " $ self.Hostname $ " to " $ self.Ip);
    }
    // Set destination port
    Addr.Port = self.Port;
    // Bind source port
    self.BindPort();
    // Attempt to open socket
    self.Open(Addr);
}

/**
 * Trigger an error whenever hostname resolving fails
 * 
 * @return  void
 */
event ResolveFailed()
{
    log(self $ " failed to resolve " $ self.Hostname);
    self.TriggerLinkFailure(LE_RESOLVE, "unable to resolve " $ self.Hostname);
}

/**
 * Switch to idle state whenever a connection is accepted
 * 
 * @return  void
 */
event Opened()
{
    log(self $ " has been opened");
    self.TriggerLinkReady();
}

/**
 * Call the delegate whenever data is received
 * Check whether response length fits into the response length limit
 * 
 * @param   string Data
 *          Received data
 * @return  void
 */
event ReceivedText(string Data)
{
    log(self $ " received (" $ Len(Data) $ ") bytes from " $ self.Hostname);
    // Only receive data while in a reading state
    if (self.State != STATE_READING)
    {
        log(self $ " ignored data from " $ self.Hostname);
        return;
    }
    // Count length of the ongoing response
    self.ResponseLength += Len(Data);
    // Make sure response length fits into the limit
    if (self.ResponseLength > class'Link'.const.MAX_RESPONSE_LENGTH)
    {
        self.TriggerLinkFailure(
            LE_LENGTH, "the response length of " $ self.ResponseLength $ " exceeded the limit"
        );
        return;
    }
    self.OnDataReceived(self, Data);
}

/**
 * Perform a shutdown upon a link close
 * 
 * @return  void
 */
event Closed()
{
    self.TriggerLinkClosed();
}

/**
 * Initialize the instance
 * 
 * @return  void
 */
public function Init()
{
    if (self.Ip != "")
    {
        self.Resolve(self.Ip);
        return;
    }
    self.Resolve(self.Hostname);
}

/**
 * Attempt to resolve given hostname
 * 
 * @param   string Hostname
 * @return  void
 */
public function Resolve(coerce string Hostname)
{
    self.SwitchState(STATE_RESOLVING);
    Super.Resolve(Hostname);
}

/**
 * Attempt to open a link
 * 
 * @param   struct'IpAddr' Addr
 * @return  bool
 */
public function bool Open(IpAddr Addr)
{
    self.SwitchState(STATE_OPENING);
    return Super.Open(Addr);
}

/**
 * Attempt to close current connection
 * 
 * @return bool
 */
public function bool Close()
{
    self.SwitchState(STATE_CLOSING);
    return Super.Close();
}

/**
 * Send data over open connection.
 * Return number of bytes sent
 * 
 * @param   string Data
 * @return  int
 */
public function int SendText(string Data)
{
    local int Count;
    local string Buffer;

    self.SwitchState(STATE_READING);
    // Send data in buffers
    while (Len(Data) > 0)
    {
        Buffer = Left(Data, class'Link'.const.BUFFER_SIZE);
        log("Sending " $ Len(Buffer) $ " bytes");
        //log("Sending " $ Buffer $ " of " $ Len(Buffer) $ " bytes");
        Data = Mid(Data, class'Link'.const.BUFFER_SIZE);
        Count += Super.SendText(Buffer);
    }
    return Count;
}

/**
 * Ask to see whether link is idling
 * 
 * @return  void
 */
public function Knock()
{
    if (self.State != STATE_IDLING)
    {
        return;
    }
    self.OnLinkReady(self);
}

/**
 * Free the link instance
 * 
 * @return  void
 */
public function Free()
{
    self.SwitchState(STATE_FREEING);
}

/**
 * Attempt to close connection if it's still open
 * Otherwise destroy the instance
 * 
 * @return  void
 */
public function Quit()
{
    if (self.IsConnected())
    {
        self.Close();
        return;
    }
    self.Destroy();
}

/**
 * Set a new state along with its timeout
 * 
 * @param   enum'eState' State
 *          New state
 * @return  void
 */
protected function SwitchState(eState State)
{
    log(self $ " changed state from " $ GetEnum(EState, self.State) $ " to " $ GetEnum(EState, State));

    self.State = State;

    switch (State)
    {
        case STATE_RESOLVING:
            self.Countdown = self.TimeoutResolve;
            break;
        case STATE_OPENING:
            self.Countdown = self.TimeoutOpen;
            break;
        case STATE_READING:
            self.Countdown = self.TimeoutRead;
            break;
        case STATE_IDLING:
            self.Countdown = self.TimeoutIdle;
            break;
        case STATE_FREEING:
            self.Countdown = self.TimeoutFree;
            break;
        case STATE_CLOSING:
            self.Countdown = self.TimeoutClose;
            break;
        default :
            return;
    }
}

/**
 * Switch to idling state if connection is still open
 * 
 * @return  void
 */
private function TriggerLinkReady()
{
    if (self.IsConnected())
    {
        self.SwitchState(STATE_IDLING);
        self.OnLinkReady(self);
        self.ResponseLength = 0;
        return;
    }
    self.Quit();
}

/**
 * Invoke an OnLinkClosed delegate call, then destroy the instance
 * 
 * @return  void
 */
protected function TriggerLinkClosed()
{
    log(self $ " has been closed");
    self.OnLinkClosed(self);
    self.Destroy();
}

/**
 * Send a failure signal via delegate, then destroy the instance
 * 
 * @param   enum'eLinkError' Error
 *          Error code
 * @param   string ErrorMessage
 *          Optional error message
 * @return  void
 */
protected function TriggerLinkFailure(eLinkError Error, optional string ErrorMessage)
{
    log(self $ " encountered a failure (" $ GetEnum(eLinkError, Error) $ ";" $ ErrorMessage $ ")");
    self.OnLinkFailure(self, Error, ErrorMessage);
    self.Quit();
}

/**
 * Return current link state
 * 
 * @return  enum'eState'
 */
public function eState GetState()
{
    return self.State;
}

/**
 * Set hostname
 * 
 * @param   string Hostname
 * @return  void
 */
public function SetHostname(string Hostname)
{
    self.Hostname = Hostname;
}

/**
 * Set destination port
 * 
 * @param   int Port
 * @return  void
 */
public function SetPort(int Port)
{
    self.Port = Port;
}

/**
 * Set host ip address
 * 
 * @param   string Ip
 * @return  void
 */
public function SetIp(string Ip)
{
    self.Ip = Ip;
}

/**
 * Return destination port
 * 
 * @return  int
 */
public function int GetPort()
{
    return self.Port;
}

/**
 * Return destination address
 * 
 * @return  string
 */
public function string GetHostname()
{
    return self.Hostname;
}

event Destroyed()
{
    self.SwitchState(STATE_NONE);
    self.OnLinkDestroyed(self);

    self.OnHostnameResolved = None;
    self.OnLinkReady = None;
    self.OnLinkClosed = None;
    self.OnDataReceived = None;
    self.OnLinkFailure = None;
    self.OnLinkDestroyed = None;

    log(self $ " has been destroyed");

    Super.Destroyed();
}

defaultproperties
{
    TimeoutResolve=1.0;
    TimeoutOpen=1.0;
    TimeoutRead=10.0;
    TimeoutIdle=10.0;
    TimeoutFree=0.5;
    TimeoutClose=5.0;
}

/* vim: set ft=java: */