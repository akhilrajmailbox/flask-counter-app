import os
from rediscluster import StrictRedisCluster
from flask import Flask
# from redis import Redis


app = Flask(__name__)

# redis = Redis.from_url(os.environ.get('REDIS_URL', 'redis://localhost:6379/0'))
#startup_nodes = [{"host": "redis-cluster.redis.svc.cluster.local", "port": "6379"}]
startup_nodes = [{"host": (os.environ.get('REDIS_URL', 'redis-cluster')), "port": "6379"}]
redis = StrictRedisCluster(startup_nodes=startup_nodes, decode_responses=True)

@app.route('/')
def hello_world():
    counter = redis.incr('counter')
    return 'Counter: %d' % counter