import org.apache.hadoop.fs.Path
import org.apache.spark.sql.SparkSession
import org.apache.spark.sql.functions._
import org.apache.spark.sql.types._

object SalesEtl {
  def run(): Unit = {
    val spark = SparkSession.builder().enableHiveSupport().getOrCreate()
    val sc = spark.sparkContext
    val input = spark.conf.get("spark.hw4.input")
    val db = spark.conf.get("spark.hw4.database")
    val table = spark.conf.get("spark.hw4.table")

    println(s"==> Spark ${spark.version}: master=${sc.master}, application=${sc.applicationId}")
    println(s"==> HDFS: ${sc.hadoopConfiguration.get("fs.defaultFS")}, metastore: ${sc.hadoopConfiguration.get("hive.metastore.uris")}")

    val rawSchema = StructType(
      Seq("order_id", "order_date", "region", "product", "quantity", "price").map(StructField(_, StringType)))
    val raw = spark.read.option("header", "true").schema(rawSchema).csv(input)
    println(s"==> Прочитано строк из $input: ${raw.count()}")

    val sales = raw
      .select(
        col("order_id").cast(LongType).as("order_id"),
        to_date(col("order_date"), "yyyy-MM-dd").as("order_date"),
        trim(col("region")).as("region"),
        trim(col("product")).as("product"),
        col("quantity").cast(IntegerType).as("quantity"),
        col("price").cast(DecimalType(10, 2)).as("price"))
      .where(col("order_id").isNotNull && col("order_date").isNotNull && col("quantity") > 0 && col("price").isNotNull)
      .withColumn("revenue", (col("quantity") * col("price")).cast(DecimalType(12, 2)))
      .withColumn("sale_year", year(col("order_date")))
      .withColumn("sale_month", month(col("order_date")))
    println(s"==> Корректных строк после приведения типов: ${sales.count()}")

    val monthly = sales
      .groupBy("sale_year", "sale_month", "region", "product")
      .agg(
        count(lit(1)).as("orders"),
        sum("quantity").cast(LongType).as("units"),
        sum("revenue").cast(DecimalType(14, 2)).as("revenue"),
        avg("price").cast(DecimalType(10, 2)).as("avg_price"))
      .select("region", "product", "orders", "units", "revenue", "avg_price", "sale_year", "sale_month")

    spark.sql(s"CREATE DATABASE IF NOT EXISTS $db")
    spark.sql(s"DROP TABLE IF EXISTS $db.$table")
    val location = new Path(new Path(spark.catalog.getDatabase(db).locationUri), table)
    val fs = location.getFileSystem(sc.hadoopConfiguration)
    if (fs.exists(location)) fs.delete(location, true)

    monthly
      .repartition(col("sale_year"), col("sale_month"))
      .write
      .format("orc")
      .mode("overwrite")
      .partitionBy("sale_year", "sale_month")
      .saveAsTable(s"$db.$table")

    val saved = spark.table(s"$db.$table")
    println(s"==> Таблица $db.$table: ${saved.count()} строк, партиций: ${spark.sql(s"SHOW PARTITIONS $db.$table").count()}")
    saved.groupBy("sale_year", "sale_month")
      .agg(sum("orders").as("orders"), sum("revenue").as("revenue"))
      .orderBy("sale_year", "sale_month")
      .show(12, false)
  }
}

try {
  SalesEtl.run()
  sys.exit(0)
} catch {
  case e: Throwable =>
    e.printStackTrace()
    sys.exit(1)
}
