FROM ubuntu:latest
RUN apt update && apt install curl unzip -y && curl -O https://sfc-repo.snowflakecomputing.com/snowsql/bootstrap/1.3/linux_aarch64/snowsql-1.4.1-linux_aarch64.bash && chmod +x snowsql-1.4.1-linux_aarch64.bash
ENV SNOWSQL_DEST=/bin 
ENV SNOWSQL_LOGIN_SHELL=/root/.profile 
RUN bash snowsql-1.4.1-linux_aarch64.bash