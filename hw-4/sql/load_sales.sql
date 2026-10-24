CREATE DATABASE IF NOT EXISTS ${hivevar:db};
USE ${hivevar:db};

CREATE EXTERNAL TABLE IF NOT EXISTS sales_staging (
  order_id   BIGINT,
  order_date DATE,
  region     STRING,
  product    STRING,
  quantity   INT,
  price      DECIMAL(10,2)
)
ROW FORMAT DELIMITED FIELDS TERMINATED BY ','
STORED AS TEXTFILE
LOCATION '${hivevar:staging}'
TBLPROPERTIES ('skip.header.line.count' = '1');

CREATE TABLE IF NOT EXISTS sales (
  order_id   BIGINT,
  order_date DATE,
  region     STRING,
  product    STRING,
  quantity   INT,
  price      DECIMAL(10,2)
)
PARTITIONED BY (sale_year INT, sale_month INT)
STORED AS ORC;

SET hive.exec.dynamic.partition = true;
SET hive.exec.dynamic.partition.mode = nonstrict;

INSERT OVERWRITE TABLE sales PARTITION (sale_year, sale_month)
SELECT order_id, order_date, region, product, quantity, price,
       year(order_date)  AS sale_year,
       month(order_date) AS sale_month
FROM sales_staging
WHERE order_id IS NOT NULL AND order_date IS NOT NULL;
