#!/usr/bin/env python3.6

import http.server
import socketserver
import subprocess

PORT = 8000

test_data = """\
TOPIC                    PARTITION  CURRENT-OFFSET  LOG-END-OFFSET  LAG             CONSUMER-ID                                         HOST            CLIENT-ID
ztf_20180430_programid2  9          1246            1246            0               zads-mirror-3-f9249a2f-6c92-4e98-bc23-0c8b1ca50b3a  /172.18.0.1     zads-mirror-3
ztf_20180427_programid2  9          24996           24996           0               zads-mirror-3-f9249a2f-6c92-4e98-bc23-0c8b1ca50b3a  /172.18.0.1     zads-mirror-3
ztf_20180309_programid0  9          -               14558           -               zads-mirror-3-f9249a2f-6c92-4e98-bc23-0c8b1ca50b3a  /172.18.0.1     zads-mirror-3
ztf_20180420_programid2  9          -               5172            -               zads-mirror-3-f9249a2f-6c92-4e98-bc23-0c8b1ca50b3a  /172.18.0.1     zads-mirror-3
ztf_20180322_programid2  9          -               443             -               zads-mirror-3-f9249a2f-6c92-4e98-bc23-0c8b1ca50b3a  /172.18.0.1     zads-mirror-3
"""

def describe_consumer_group(group):
    out = subprocess.check_output(["/usr/bin/kafka-consumer-groups", "--bootstrap-server", "epyc.astro.washington.edu:9092", "--group", group, "--describe"]).decode('utf-8')
#    out = test_data
    lines = [ line.split() for line in out.split('\n')]
    lines = [ line for line in lines if len(line) == 8 ]	# remove anything that's not well formatted
    if(lines[0][0] == "TOPIC"): lines.pop(0)			# remove header

    for (topic, partition, curoffs, endoffs, lag, consumerid, host, clientid) in lines:
        if(curoffs == '-'): curoffs = "NaN"
        if(endoffs == '-'): endoffs = "NaN"
        if(lag == '-'): lag = "NaN"
        yield f'current_offset{{group="{group}", topic="{topic}", partition="{partition}"}} = {curoffs}'
        yield f'endoffs_offset{{group="{group}", topic="{topic}", partition="{partition}"}} = {endoffs}'
        yield f'lag_offset{{group="{group}", topic="{topic}", partition="{partition}"}} = {lag}'

class RequestHandler(http.server.BaseHTTPRequestHandler):
    def do_HEAD(self):
        self.send_response(200)
        self.send_header('Content-type', 'text/plain')
        self.end_headers()

    def do_GET(self):
        try:
            result = '\n'.join(describe_consumer_group("zads-mirror"))
        except:
            self.send_response(500)
            self.send_header('Content-type', 'text/plain')
            self.end_headers()
            raise

        self.do_HEAD()
        self.wfile.write(result.encode("utf-8"))
        self.wfile.write('\n'.encode("utf-8"))

#group="zads-mirror"
#out = subprocess.check_output(["/usr/bin/kafka-consumer-groups", "--bootstrap-server", "epyc.astro.washington.edu:9092", "--group", group, "--describe"]).decode('utf-8')
#print("[[" + out + "]]")
#exit(0)

Handler = RequestHandler

with socketserver.TCPServer(("", PORT), Handler) as httpd:
    print("serving at port", PORT)
    httpd.serve_forever()
