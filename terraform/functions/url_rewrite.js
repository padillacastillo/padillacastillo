// Appends index.html to directory-style requests before they reach the
// private S3 origin. Without this, a request for /resume falls through with
// no object at that exact key - S3's own "index document" behavior only
// applies when served directly from S3, not through CloudFront/OAC.
function handler(event) {
    var request = event.request;
    var uri = request.uri;

    if (uri.endsWith('/')) {
        request.uri += 'index.html';
    } else if (!uri.includes('.')) {
        request.uri += '/index.html';
    }

    return request;
}
