## Fix server going silent after sending a large response

After sending a large response, a server could stop reading anything further from that connection — additional requests on a keep-alive connection would never reach your handlers. No error was raised and the connection was not closed; it simply went quiet, even though the client was still sending. This most often showed up when sending or streaming large responses. Incoming requests are now delivered as expected.
