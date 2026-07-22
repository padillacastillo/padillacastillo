// Unused - no longer associated with the distribution. Kept only so the
// aws_cloudfront_function resource in hosting.tf has code to reference until
// it's deleted in a follow-up apply. See the resource's comment for why.
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
