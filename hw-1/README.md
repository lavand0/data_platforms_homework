# HDFS-кластер: NameNode, Secondary NameNode, 3 DataNode

Hadoop 3.4.3, OpenJDK 11. Фактор репликации 3. Скрипты запускаются с edge-ноды `team-17-en`.

| Узел | Сервисы |
| --- | --- |
| `team-17-nn` | NameNode, DataNode |
| `team-17-00` | Secondary NameNode, DataNode |
| `team-17-01` | DataNode |

Хосты, роли, версии и пути задаются в `config/cluster.env`.

## Автоматическое развёртывание

```bash
ssh team@178.236.27.243
git clone https://github.com/<логин>/hdfs-cluster-deploy.git
cd hdfs-cluster-deploy
./deploy.sh
```

`deploy.sh` по очереди запускает:

1. `scripts/00-check-access.sh` — проверяет ssh и sudo на узлах;
2. `scripts/01-prepare-nodes.sh` — настраивает `/etc/hosts`, ставит Java, создаёт пользователя `hadoop` и каталоги;
3. `scripts/02-install-hadoop.sh` — скачивает Hadoop, проверяет SHA-512 и устанавливает его на все узлы;
4. `scripts/03-configure.sh` — генерирует конфиги из `config/templates/` и раскладывает их на узлы;
5. `scripts/04-start-cluster.sh` — форматирует NameNode, если она ещё не отформатирована, и запускает демоны;
6. `scripts/05-check-cluster.sh` — проверяет кластер.

Повторный запуск безопасен: NameNode не форматируется заново.

```bash
./scripts/stop-cluster.sh       # остановить кластер
./scripts/destroy-cluster.sh    # остановить и стереть данные HDFS
```

## Ручное развёртывание

Команды выполняются от root (`sudo -i`). На внутренние узлы: `ssh -i ~/.ssh/team_internal team@<узел>`.

**1. Подготовка — на всех узлах**

```bash
# строка 127.0.1.1 <hostname> заставляет NameNode слушать только loopback
sed -i '/^127\.0\.1\.1/d' /etc/hosts
cat >> /etc/hosts <<'EOF'
10.17.0.10 team-17-en
10.17.0.11 team-17-nn
10.17.0.12 team-17-00
10.17.0.13 team-17-01
EOF

apt-get update && apt-get install -y openjdk-11-jdk-headless
useradd -m -s /bin/bash -U hadoop
mkdir -p /data/hadoop/{nn,snn,dn,pids} /var/log/hadoop
chown -R hadoop:hadoop /data/hadoop /var/log/hadoop
chmod 700 /data/hadoop/dn
```

**2. Установка Hadoop**

На edge-ноде скачать архив и раздать его на узлы:

```bash
curl -fLO https://dlcdn.apache.org/hadoop/common/hadoop-3.4.3/hadoop-3.4.3.tar.gz
for h in team-17-nn team-17-00 team-17-01; do scp -i ~/.ssh/team_internal hadoop-3.4.3.tar.gz team@$h:/tmp/; done
```

На каждом узле:

```bash
tar -xzf /tmp/hadoop-3.4.3.tar.gz -C /opt
ln -sfn /opt/hadoop-3.4.3 /opt/hadoop
chown -R hadoop:hadoop /opt/hadoop-3.4.3
```

**3. Конфигурация — на всех узлах одинаковая**, в `/opt/hadoop/etc/hadoop/`. Готовые шаблоны лежат в `config/templates/`.

| Файл | Параметр | Значение |
| --- | --- | --- |
| `core-site.xml` | `fs.defaultFS` | `hdfs://team-17-nn:9000` |
| `hdfs-site.xml` | `dfs.replication` | `3` |
| | `dfs.namenode.name.dir` | `file:///data/hadoop/nn` |
| | `dfs.namenode.http-address` | `team-17-nn:9870` |
| | `dfs.namenode.secondary.http-address` | `team-17-00:9868` |
| | `dfs.namenode.checkpoint.dir` | `file:///data/hadoop/snn` |
| | `dfs.datanode.data.dir` | `file:///data/hadoop/dn` |
| `workers` | | `team-17-nn`, `team-17-00`, `team-17-01` (по одному на строку) |

В конец `hadoop-env.sh`:

```bash
export JAVA_HOME=/usr/lib/jvm/java-11-openjdk-amd64
export HADOOP_LOG_DIR=/var/log/hadoop
export HADOOP_PID_DIR=/data/hadoop/pids
```

**4. Запуск**

```bash
# team-17-nn: форматирование (только один раз) и NameNode
sudo -u hadoop /opt/hadoop/bin/hdfs namenode -format -nonInteractive -clusterId team-17-hdfs
sudo -u hadoop /opt/hadoop/bin/hdfs --daemon start namenode

# team-17-nn, team-17-00, team-17-01
sudo -u hadoop /opt/hadoop/bin/hdfs --daemon start datanode

# team-17-00
sudo -u hadoop /opt/hadoop/bin/hdfs --daemon start secondarynamenode
```

## Проверка

```bash
./scripts/05-check-cluster.sh
```

Скрипт проверяет демоны, 3 живых DataNode без мёртвых и устаревших, safe mode, запись файла с `Live_repl=3`,
`fsck /` и отсутствие ERROR/FATAL в логах. В конце выводится `ИТОГ: кластер целостный`, отчёт сохраняется в `reports/`.

Вручную на `team-17-nn`:

```bash
sudo -u hadoop /opt/hadoop/bin/hdfs dfsadmin -report   # Live datanodes (3), Dead datanodes (0)
sudo -u hadoop /opt/hadoop/bin/hdfs fsck /             # Status: HEALTHY
grep -E ' (ERROR|FATAL) ' /var/log/hadoop/*.log        # пусто (на каждом узле)
```

Веб-интерфейс NameNode — через туннель с локальной машины:

```bash
ssh -L 9870:team-17-nn:9870 team@178.236.27.243
```

На <http://localhost:9870> должно быть `Live Nodes: 3` и `Dead Nodes: 0`.

![NameNode UI](docs/namenode-ui.png)
