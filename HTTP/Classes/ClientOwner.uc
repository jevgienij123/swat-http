interface ClientOwner;

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

import enum eClientError from Client;

/**
 * ClientOwner interface that must be implemented by
 * a class in order to allow its instances to communicate
 * with a http client (i.e. to send HTTP requests and receieve response).
 */

/**
 * This method is designed to be invoked
 * whenever a successful and properly formed HTTP response is received
 *
 * @param   int StatusCode
 *          Response code (e.g. 200)
 * @param   string Response
 *          Respose body
 * @param   string Hostname
 *          Host name
 * @param   int Port
 *          Host port
 * @return  void
 */
public function OnRequestSuccess(int StatusCode, string Response, string Hostname, int Port);

/**
 * This method is supposed to be invoked whenever 
 * client fails to either send request or to receive a proper response
 *
 * @param   enum'eClientError' ErrorCode
 *          Error code
 * @param   string ErrorMessage
 *          Error message
 * @param   string Hostname
 *          Host name
 * @param   int Port
 *          Host port
 * @return  void
 */
public function OnRequestFailure(eClientError ErrorCode, string ErrorMessage, string Hostname, int Port);

/* vim: set ft=java: */