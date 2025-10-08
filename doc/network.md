# network.sh

Utilities for network

## Overview

This module contains functions to work with network connection.

**DYBATPHO_CURL_MAX_RETRIES** (number): Max number of retries when using `curl` failed

## Index

* [__get_http_code](#gethttpcode)
* [dybatpho::curl_do](#dybatphocurldo)
* [dybatpho::curl_download](#dybatphocurldownload)

### __get_http_code

Get description of HTTP status code

#### Arguments

* **$1** (string): Status code

#### Output on stdout

* Description of status code

### dybatpho::curl_do

Transferring data with URL by curl

#### Example

```bash
dybatpho::curl_do https://example.com /tmp/1
dybatpho::curl_do https://example.com /tmp/1 --compressed
```

#### Arguments

* **$1** (string): URL
* **$2** (string): Location of curl output, default is `/dev/null`
* **$3** (string): Other options/arguments for curl

#### Exit codes

* **0**: Transferred data
* **1**: Unknown error
* **3**: First digit of HTTP error code 3xx
* **4**: First digit of HTTP error code 4xx
* **5**: First digit of HTTP error code 5xx
* **127**: Curl isn't installed

### dybatpho::curl_download

Download file

#### Arguments

* **$1** (string): URL
* **$2** (string): Destination of file to download
* **...** (string): Other options/arguments for curl

#### Exit codes

* **2**: Can't create folder of destination file

#### See also

* [dybatpho::curl_do](#dybatphocurldo)

