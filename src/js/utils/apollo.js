const {
  ApolloClient,
  HttpLink,
  InMemoryCache,
} = require("@apollo/client/core");
const fetch = require("node-fetch");

const createApolloClient = (uri) =>
  new ApolloClient({
    link: new HttpLink({
      uri,
      fetch,
    }),
    cache: new InMemoryCache(),
  });

module.exports = {
  createApolloClient,
};
