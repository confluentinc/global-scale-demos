FROM ubuntu:latest

RUN apt update && apt install curl unzip mysql-client -y 

ARG HARDWARE=Aarch64

RUN if [ "$HARDWARE" = "Aarch64" ]; then \
      curl -O https://sfc-repo.snowflakecomputing.com/snowsql/bootstrap/1.4/linux_aarch64/snowsql-1.4.4-linux_aarch64.bash && \
      mv snowsql-1.4.4-linux_aarch64.bash snowsql.bash; \
    elif [ "$HARDWARE" = "MAC" ]; then \
      curl -O https://sfc-repo.snowflakecomputing.com/snowsql/bootstrap/1.4/mac/snowsql-1.4.4-darwin_x86_64.pkg && \
      echo "macOS version downloaded (though not usable inside Docker)"; \
    elif [ "$HARDWARE" = "x86_64" ]; then \
      curl -O https://sfc-repo.snowflakecomputing.com/snowsql/bootstrap/1.4/linux_x86_64/snowsql-1.4.4-linux_x86_64.bash && \
      mv snowsql-1.4.4-linux_x86_64.bash snowsql.bash; \
    else \
      echo "Unsupported architecture: $HARDWARE" && exit 1; \
    fi

ENV SNOWSQL_DEST=/bin 
ENV SNOWSQL_LOGIN_SHELL=/root/.profile 

RUN bash snowsql.bash
