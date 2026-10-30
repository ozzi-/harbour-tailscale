#ifndef CLIENT_H
#define CLIENT_H

#include <QObject>

class QProcess;

class Client : public QObject
{
    Q_OBJECT
public:
    explicit Client(QObject *parent = nullptr);
    virtual ~Client();

    Q_INVOKABLE void down();
    Q_INVOKABLE QString getStatus() const;
    Q_INVOKABLE QString getStatusJson() const;
    Q_INVOKABLE bool isUp() const;
    Q_INVOKABLE void startPing(const QString &address, int count);
    Q_INVOKABLE void cancelPing();
    Q_INVOKABLE QString getVersion() const;
    Q_INVOKABLE void up();
    Q_INVOKABLE bool acceptRoutes() const;
    Q_INVOKABLE void setAcceptRoutes(bool enabled);
    Q_INVOKABLE void applyAcceptRoutes();
    Q_INVOKABLE void setExitNode(const QString &node);
    Q_INVOKABLE void unsetExitNode();

Q_SIGNALS:
    void loginRequest(QString url);
    void statusUpdate(bool isUp);
    void pingSample(double latencyMs, bool relayed);
    void pingFinished();

private:
    QProcess *m_cmd;
    QProcess *m_ping;
    QString m_pingBuffer;

    void onUpReadyRead();
    void onUpFinished(int exitCode);
    void onPingReadyRead();
    void onPingFinished(int exitCode);
};

#endif // CLIENT_H
