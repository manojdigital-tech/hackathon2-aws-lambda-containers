exports.handler = async (event) => {
  return {
    statusCode: 200,
    headers: { "content-type": "application/json" },
    body: JSON.stringify({ service: "orders", method: event?.requestContext?.http?.method || "N/A" }),
  };
};
