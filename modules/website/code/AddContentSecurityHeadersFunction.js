function handler(event) {
    var response = event.response;
    var headers = response.headers;
    
    headers['strict-transport-security'] = { value: 'max-age=63072000; includeSubdomains; preload'};
    headers['content-security-policy'] = { value: "default-src 'self'; connect-src api.acatcalledjack.co.uk www.google-analytics.com 'self';script-src 'sha256-5SS84/nmPS4fn2fFyeWoXGLTVvAoQp5n1hq+X1IueeQ=' 'sha256-zFaqiWRN51I5N/7ZrSd+pLjUwCK9VvygWxxx0MBPsq8=' 'sha256-ehPVrgdV2GwJCE7DAMSg8aCgaSH3TZmA66nZZv8XrTg=' 'sha256-HWI9/ZF/JMmbF+fLOE7j99deAvaDjNjPLr3WV0tloHk=' 'sha256-bxhg9yQJsE9H8cmRL9pftg8B7roBqEMvF8RaDPZAJNM=' 'sha256-TeCqDSllXfeq/9Zx8W5SqJ1oGVYd2Ij/r0g0U9jB4rI=' 'sha256-TAjtDIqn9cHEay2zFIPQbcOk8cJEbvSgrqLTbdWAnyc=' 'sha256-RzaL5dOzgVuWkSVGjFGdrZ2ynANWCyjw7XQkOQZms1k=' 'sha256-26HUa9ro1U+M0WJ0j0y224oFJCkAZ3tApoEHu0QU2m8=' 'sha256-dNu1cjYb/BXRPx3PeIYWZkXGk+8CCxVpFbxkX1C/R5Q=' 'sha256-7E3QwvOUCVIBH+AeRYH0BqSXkERpJb1ENb5F+5V1kPE=' 'sha256-i8unXKO3PFLzt2ImNvHL5fgq7rK+YheCVA6TNESuSeY=' 'sha256-hLhGQSix5XadFCGWIg3M6Th2VPZeSAyYEK+sfteAOoU=' 'sha256-9EG9hMLiIghk3q49uP4R3wRgwZGVXJHsFGpjBjs3/XA=' 'sha256-bg2g7ScT07iu5pcs4/kwnAUd1zpnE/rjE7R/zwx9kwE=' 'sha256-jy3wMM74gav8/XjcMn+iOsM7nNf55hVt1Ba6X3H7NS8=' www.googletagmanager.com www.google-analytics.com 'self';img-src www.googletagmanager.com www.google-analytics.com 'self'; font-src fonts.gstatic.com 'self'; style-src 'self' 'unsafe-inline'; style-src-elem fonts.googleapis.com 'self' 'unsafe-inline'; object-src 'none'; frame-ancestors 'none'; base-uri 'self'; form-action 'self' api.acatcalledjack.co.uk"};
    headers['x-content-type-options'] = { value: 'nosniff'};
    headers['x-frame-options'] = {value: 'DENY'};
    headers['x-xss-protection'] = {value: '1; mode=block'};
    headers['referrer-policy'] = {value: 'same-origin'};
    
    return response;
}