"""Loopback-only synthetic download server. Never contacts production endpoints."""
from http.server import ThreadingHTTPServer, BaseHTTPRequestHandler
from pathlib import Path
import json,sys
state_path,port_path=map(Path,sys.argv[1:])
class Handler(BaseHTTPRequestHandler):
    def log_message(self,*args):pass
    def handle_request(self,head=False):
        state=json.loads(state_path.read_text(encoding='utf-8-sig'))
        state['heads' if head else 'gets']=state.get('heads' if head else 'gets',0)+1
        state_path.write_text(json.dumps(state))
        if state.get('status',200)!=200:
            self.send_error(state['status']);return
        data=state.get('body','AQSECR01synthetic-only').encode()
        self.send_response(200)
        if not state.get('omit_modified'):self.send_header('Last-Modified',state.get('modified','Fri, 23 Oct 2026 12:00:00 GMT'))
        if not state.get('omit_length'):self.send_header('Content-Length',str(len(data)+(50 if state.get('truncate') else 0)))
        self.end_headers()
        if not head:self.wfile.write(data)
    def do_HEAD(self):self.handle_request(True)
    def do_GET(self):self.handle_request()
server=ThreadingHTTPServer(('127.0.0.1',0),Handler)
port_path.write_text(str(server.server_port))
server.serve_forever()
