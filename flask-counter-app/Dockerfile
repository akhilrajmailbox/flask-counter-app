FROM python:3.7-slim

ADD . /opt/app/
WORKDIR /opt/app/
RUN pip install -r requirements.txt

ENTRYPOINT gunicorn app:app -b :5000 -k gevent
EXPOSE 5000/tcp