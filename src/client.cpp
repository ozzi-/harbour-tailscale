/*
  The MIT License (MIT)

  Copyright (c) 2022 Andrea Scarpino <andrea@scarpino.dev>

  Permission is hereby granted, free of charge, to any person obtaining a copy
  of this software and associated documentation files (the "Software"), to deal
  in the Software without restriction, including without limitation the rights
  to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
  copies of the Software, and to permit persons to whom the Software is
  furnished to do so, subject to the following conditions:

  The above copyright notice and this permission notice shall be included in all
  copies or substantial portions of the Software.

  THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
  IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
  FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
  AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
  LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
  OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
  SOFTWARE.
*/

#include "client.h"

#include <QDir>
#include <QProcess>
#include <QRegularExpression>
#include <QRegularExpressionMatch>
#include <QSettings>
#include <QStandardPaths>

namespace {

QString settingsFilePath()
{
    const QString dir = QStandardPaths::writableLocation(QStandardPaths::AppConfigLocation);
    QDir().mkpath(dir);
    return dir + QStringLiteral("/settings.conf");
}

} // namespace

Client::Client(QObject *parent)
    : QObject(parent)
    , m_cmd(0)
    , m_ping(0)
{}

Client::~Client() {}

QString Client::getStatus() const
{
    QProcess cmd;
    cmd.start(QStringLiteral("/usr/bin/tailscale"), QStringList("status"));
    cmd.setProcessChannelMode(QProcess::MergedChannels);
    cmd.waitForFinished();

    return QString(cmd.readAllStandardOutput());
}

QString Client::getStatusJson() const
{
    QProcess cmd;
    cmd.start(QStringLiteral("/usr/bin/tailscale"),
              QStringList() << QStringLiteral("status") << QStringLiteral("--json"));
    cmd.setProcessChannelMode(QProcess::MergedChannels);
    cmd.waitForFinished();

    return QString(cmd.readAllStandardOutput());
}

void Client::startPing(const QString &address, int count)
{
    cancelPing();
    m_pingBuffer.clear();

    m_ping = new QProcess(this);
    m_ping->setProcessChannelMode(QProcess::MergedChannels);
    connect(m_ping, &QProcess::readyReadStandardOutput, this, &Client::onPingReadyRead);
    connect(m_ping, (void (QProcess::*)(int)) &QProcess::finished, this, &Client::onPingFinished);

    // --until-direct=false: force ALL <count> pings. By default `tailscale ping`
    // stops as soon as a direct (non-DERP) path is found, which would give far
    // fewer samples than requested (we saw "1 of 10" on relayed links).
    m_ping->start(QStringLiteral("/usr/bin/tailscale"),
                  QStringList() << QStringLiteral("ping")
                                << QStringLiteral("--c=%1").arg(count)
                                << QStringLiteral("--until-direct=false")
                                << QStringLiteral("--timeout=4s")
                                << address);
}

void Client::cancelPing()
{
    if (m_ping) {
        m_ping->kill();
        m_ping->deleteLater();
        m_ping = 0;
    }
    m_pingBuffer.clear();
}

namespace {
    // "pong from name (ip) via DERP(x) in 151ms" → latency + whether relayed
    bool parsePingLine(const QString &line, double &ms, bool &relayed)
    {
        if (!line.startsWith(QStringLiteral("pong")))
            return false;
        static const QRegularExpression re(QStringLiteral(" in ([0-9]+(?:\\.[0-9]+)?)\\s*ms"));
        const QRegularExpressionMatch m = re.match(line);
        ms = m.hasMatch() ? m.captured(1).toDouble() : 0.0;
        relayed = line.contains(QStringLiteral(" via "));
        return true;
    }
} // namespace

void Client::onPingReadyRead()
{
    if (!m_ping)
        return;

    m_pingBuffer += QString::fromUtf8(m_ping->readAllStandardOutput());
    int nl;
    while ((nl = m_pingBuffer.indexOf(QLatin1Char('\n'))) != -1) {
        const QString line = m_pingBuffer.left(nl).trimmed();
        m_pingBuffer = m_pingBuffer.mid(nl + 1);

        double ms = 0.0;
        bool relayed = false;
        if (parsePingLine(line, ms, relayed))
            Q_EMIT pingSample(ms, relayed);
    }
}

void Client::onPingFinished(int exitCode)
{
    Q_UNUSED(exitCode);

    // Flush any trailing line that never received a newline
    onPingReadyRead();
    const QString line = m_pingBuffer.trimmed();
    m_pingBuffer.clear();
    double ms = 0.0;
    bool relayed = false;
    if (parsePingLine(line, ms, relayed))
        Q_EMIT pingSample(ms, relayed);

    if (m_ping) {
        m_ping->deleteLater();
        m_ping = 0;
    }

    Q_EMIT pingFinished();
}

void Client::up()
{
    m_cmd = new QProcess(this);
    m_cmd->setProcessChannelMode(QProcess::MergedChannels);

    connect(m_cmd, (void (QProcess::*)(int)) &QProcess::finished, this, &Client::onUpFinished);
    connect(m_cmd, &QProcess::readyReadStandardOutput, this, &Client::onUpReadyRead);

    m_cmd->start(QStringLiteral("/usr/bin/tailscale"), QStringList("up"));
}

void Client::onUpFinished(int exitCode)
{
    if (exitCode == 0) {
        Q_EMIT statusUpdate(true);
    }
    m_cmd->deleteLater();
    m_cmd = 0;
}

void Client::onUpReadyRead()
{
    static const QRegularExpression regexp("(https://login\\.tailscale\\.com/a/\\S+)");

    QRegularExpressionMatch match = regexp.match(m_cmd->readAllStandardOutput());
    if (match.hasMatch()) {
        Q_EMIT loginRequest(match.captured(1));
    }
}

void Client::down()
{
    QProcess cmd;
    cmd.start(QStringLiteral("/usr/bin/tailscale"), QStringList("down"));
    cmd.waitForFinished();

    Q_EMIT statusUpdate(false);
}

bool Client::isUp() const
{
    QProcess cmd;
    cmd.start(QStringLiteral("/usr/bin/tailscale"), QStringList("status"));
    cmd.waitForFinished();

    return cmd.exitCode() == 0;
}

QString Client::getVersion() const
{
    QProcess cmd;
    cmd.start(QStringLiteral("/usr/bin/tailscale"), QStringList("version"));
    cmd.waitForFinished();

    return cmd.readAllStandardOutput();
}

bool Client::acceptRoutes() const
{
    QSettings settings(settingsFilePath(), QSettings::IniFormat);
    return settings.value(QStringLiteral("acceptRoutes"), false).toBool();
}

void Client::setAcceptRoutes(bool enabled)
{
    QSettings settings(settingsFilePath(), QSettings::IniFormat);
    settings.setValue(QStringLiteral("acceptRoutes"), enabled);
}

void Client::applyAcceptRoutes()
{
    QSettings settings(settingsFilePath(), QSettings::IniFormat);
    const bool enabled = settings.value(QStringLiteral("acceptRoutes"), false).toBool();

    QProcess cmd;
    cmd.start(QStringLiteral("/usr/bin/tailscale"),
              QStringList() << QStringLiteral("set")
                            << (enabled ? QStringLiteral("--accept-routes")
                                        : QStringLiteral("--accept-routes=false")));
    cmd.waitForFinished();
}

void Client::setExitNode(const QString &node)
{
    QProcess cmd;
    cmd.start(QStringLiteral("/usr/bin/tailscale"),
              QStringList() << QStringLiteral("set") << QStringLiteral("--exit-node=%1").arg(node));
    cmd.waitForFinished();
}

void Client::unsetExitNode()
{
    QProcess cmd;
    cmd.start(QStringLiteral("/usr/bin/tailscale"),
              QStringList() << QStringLiteral("set") << QStringLiteral("--exit-node="));
    cmd.waitForFinished();
}
