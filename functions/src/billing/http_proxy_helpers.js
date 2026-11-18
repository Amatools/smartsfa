async function proxyBillingRequestToFunction({
  request,
  response,
  targetUrl,
  method,
  extraResponseFields,
  fetchImpl = fetch,
  timeoutMs = 40000,
}) {
  const authHeader = String(request.headers?.authorization ?? '').trim();
  const headers = {
    Accept: 'application/json',
  };
  if (authHeader) {
    headers.Authorization = authHeader;
  }

  let requestUrl = targetUrl;
  let body;

  if (method === 'GET') {
    const sourceQuery = request.query || {};
    const searchParams = new URLSearchParams();
    for (const [key, value] of Object.entries(sourceQuery)) {
      if (Array.isArray(value)) {
        for (const item of value) {
          if (item != null) {
            searchParams.append(key, String(item));
          }
        }
      } else if (value != null) {
        searchParams.append(key, String(value));
      }
    }

    const queryString = searchParams.toString();
    if (queryString) {
      requestUrl = `${targetUrl}?${queryString}`;
    }
  } else {
    headers['Content-Type'] = 'application/json';
    body = JSON.stringify(
      request.body && typeof request.body === 'object' ? request.body : {},
    );
  }

  let upstreamResponse;
  try {
    upstreamResponse = await fetchImpl(requestUrl, {
      method,
      headers,
      body,
      signal: AbortSignal.timeout(timeoutMs),
    });
  } catch (error) {
    response.status(502).json({
      error: 'provider_proxy_failed',
      message: error instanceof Error ? error.message : String(error),
      ...extraResponseFields,
    });
    return;
  }

  const rawText = await upstreamResponse.text();
  let parsedPayload = null;
  try {
    parsedPayload = JSON.parse(rawText);
  } catch (_) {
    parsedPayload = null;
  }

  if (parsedPayload && typeof parsedPayload === 'object' && !Array.isArray(parsedPayload)) {
    response.status(upstreamResponse.status).json({
      ...parsedPayload,
      ...extraResponseFields,
    });
    return;
  }

  response.status(upstreamResponse.status).json({
    rawBody: rawText,
    ...extraResponseFields,
  });
}

module.exports = {
  proxyBillingRequestToFunction,
};
