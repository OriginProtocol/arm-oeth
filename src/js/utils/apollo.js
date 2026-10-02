const {
  ApolloClient,
  HttpLink,
  InMemoryCache,
} = require("@apollo/client/core");
const fetch = require("node-fetch");

const createApolloClient = (uri, fetchImpl = fetch) =>
  new ApolloClient({
    link: new HttpLink({
      uri,
      fetch: fetchImpl,
      // Debian's HTTP-agent security backport can trigger node-fetch@2's
      // false premature-close error while reading chunked gzip responses.
      headers: { "Accept-Encoding": "identity" },
      fetchOptions: { compress: false },
    }),
    cache: new InMemoryCache(),
  });

module.exports = {
  createApolloClient,
};
