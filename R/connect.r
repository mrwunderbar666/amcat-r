#' Connect to the AmCAT API
#'
#' Connect to the AmCAT API and request or refresh a temporary (48h) authentication token. 
#' 
#' The token can be used in two ways. Firstly, after running amcat_connect, the token will automatically be used
#' until the R session is ended. This is recommended for occasional use. Alternatively, amcat_connect() returns
#' a connection object (amcatConnection) that can be passed to the conn argument in functions that require a connection. 
#' The amcatConnection object can be saved for use across sessions, so that the password does not have to be given to connect.
#' It is also possible to pass the amcatConnection object to amcat_connect, which will refresh the token and set it up for
#' default use within a session. 
#' 
#' @param host the hostname, e.g. https://amcat.nl or http://localhost:8000
#' @param username an existing username on the host server
#' @param token an existing token to authenticate with. If given (and valid), no password has to be entered
#' @param disable_ipv6 If True, only use ipv4 resolving (faster if ipv6 causes timeout). Defaults to true, but this may change in the future.
#' @param ssl.verifypeer If True, verifies the authenticity of the peer's certificate
#' @param conn an existing AmCAT connection object. If provided, the connection will be opened (if not yet open) and refreshed (i.e. new token). The other arguments are ignored.
#' 
#' @return A S3 class (amcatConnection) with authentication information that is used by the other functions in this package
#' @examples
#' \dontrun{
#' ## create connection
#' amcat_connect('https://amcat.nl', 'username')
#' 
#' ## optionally, get the amcatConnect object, e.g., to save it for later use
#' conn = amcat_connect('https://amcat.nl', 'username')
#' saveRDS(conn, '~/.amcat_connection.rds')
#' 
#' ## refresh connection 
#' conn = readRDS('~/.amcat_connection.rds')
#' conn = amcat_connect(conn = conn)
#' }
#' @export
amcat_connect <- function(host=NULL, username=NULL, token=NULL, disable_ipv6=TRUE, ssl.verifypeer=TRUE, conn=NULL) {
  if (is.null(conn)) {
    if (is.null(host) | is.null(username)) stop('If no connection (conn) is given, host and username are required')
    conn = structure(list(host = host, 
                          username = username,
                          token = token, 
                          ssl.verifypeer = ssl.verifypeer,
                          disable_ipv6 = disable_ipv6),
                     class = "amcatConnection")
  }
  
  ## if active connection with same host and username, use existing token
  act_conn = conn_from_env()
  if (!is.null(act_conn)) {
    if (act_conn$host == host && act_conn$username == username) conn$token = act_conn$token
  }
  
  conn$token = get_token(conn)

  conn_to_env(conn)
  invisible(conn)
}

get_opts <- function(conn) {
  opts = list(ssl.verifypeer = conn$ssl.verifypeer)
  if (!is.null(conn$token)) opts = c(opts, list(httpheader = c(Authorization=paste("Token", conn$token))))
  if (conn$disable_ipv6) opts = c(opts, list(ipresolve=1))
  opts
}

get_config <- function(conn, ...) {
  l = list(...)
  if (conn$ssl.verifypeer) l[['ssl_verifypeer']] = T
  if (conn$disable_ipv6) l[['ipresolve']] = 1
  do.call(httr::config, args = l)
}

get_headers <- function(conn, ...) {
  l = list(...)
  if (!is.null(conn$token)) l[['Authorization']] = paste("Token", conn$token)
  do.call(httr::add_headers, args = l)
}

conn_to_env <- function(conn) {
  if(!methods::is(conn, 'amcatConnection')) stop("conn is not an amcatConnection object")
  Sys.setenv(AMCAT_CONNECTION = rjson::toJSON(conn))
}


conn_from_env <- function(){
  amcat_conn = Sys.getenv('AMCAT_CONNECTION')
  if (amcat_conn == '') return(NULL)
  structure(rjson::fromJSON(amcat_conn),
            class = 'amcatConnection')
}

get_token <- function(conn, min_version='3.4.1') {
  url = httr::parse_url(conn$host)
  url$path = '/api/v4/get_token'
  
  if (!is.null(conn$token)) {
    res = get_url('/api/v4/get_token', conn=conn, post = T, read=F)
    if (!res$status_code == 200) {
      message('Token is not valid or expired. Please re-enter password')
      conn$token = NULL
    }
  }
  if (is.null(conn$token)) {
    passwd = getPass::getPass(paste('Enter AmCAT password for user', conn$username))
    res = get_url('/api/v4/get_token', conn=conn, post = T, username=conn$username, password=passwd, read=F)
    if (!res$status_code == 200) {
      stop(paste("Could not get token for ", conn$username,"@", conn$host, " please check host, username and password"))
    }
  }
  
  res = read_response(res)
  verify_version(res, min_version)
  res$token
}

verify_version <- function(res, min_version) {
  version = gsub('[a-zA-Z]*', '', res$version)
  if (compareVersion(version, min_version) < 0) {
    e = 'VERSION ERROR. This version of amcatr only works for AmCAT servers >= %s (current server runs %s). To connect to the current server, you can use an older version of amcatr hosted on github under amcat/amcat-r .'
    stop(sprintf(e, min_version, version), call. = F)
  }
}

#' S3 print method for amcatConnection (API connection) objects
#'
#' @param x an amcatConnection connection object, created with \link{amcat_connect}
#' @param ... not used
#'
#' @method print amcatConnection
#' @examples
#' \dontrun{
#' conn = amcat_connect('http://localhost:8000')
#' conn
#' }
#' @export
print.amcatConnection <- function(x, ...){
  cat(sprintf('connection to AmCAT server\nhost:\t%s\nuser:\t%s\n', x$host, x$username))
}