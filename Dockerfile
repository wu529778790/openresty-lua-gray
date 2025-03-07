FROM centos7-openresty

COPY * /
WORKDIR /
RUN mkdir /healthdir && cp ./robots.txt /healthdir/robots.txt && cp ./gray.lua /etc/nginx/gray.lua && cp ./gray.shenzjd.conf /etc/nginx/conf.d/gray-cloud.shenzjd.conf

STOPSIGNAL SIGTERM
EXPOSE 80
CMD ["nginx", "-g", "daemon off;"]
