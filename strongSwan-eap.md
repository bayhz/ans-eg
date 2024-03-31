### 先准备好证书
虽然客户端可以采用EAP认证方式，但服务器端只能通过证书认证方式，所以还是至少要创建服务器证书的。

一个证书里面包含了证书内容(主体)、公钥、签发者的签名，这3个信息。由于证书中有公钥所以就有对应的私钥，创建一个证书首先创建私钥，然后就可以创建未经过签名的REQ证书，最后使用签发机构的私钥和证书签发这个REQ证书就可以使用了。签发机构通常是知名可信任的CA，但你也可以创建一个自签名的CA证书来签发服务器证书。最后，访问配置了证书的服务器前，必须将自签名CA证书自行安装在客户端上。

证书是可以在任何地方创建的，不过由于每个证书都有对应的私钥，而私钥的设计本来就不用来在网络中传输的，所以常规就是哪里的证书就在哪里创建，然后只需要将证书在网络中传递而不用传递私钥。所以你可以在自己的个人PC中创建CA证书，在服务器中创建服务器证书(未签名)，然后传到个人PC使用CA签名后再传到服务器中。当然这些你都可以在一个设备上进行操作。

#### 创建自签名CA证书
1. 首先创建CA证书的私钥
```
pki --gen --type ed25519 --outform pem > caKey.pem
```
2. 使用这个私钥创建自签名的CA证书
```
pki --self --ca --lifetime 3652 --in caKey.pem \
--dn "C=CH, O=xx, CN=xx Root CA" \
--outform pem > caCert.pem
```

#### 创建服务器证书
1. 首先创建服务器证书的私钥
```
cd /etc/swanctl;
pki --gen --type rsa --size 3072 --outform pem > private/svrKey.pem
```
2. 使用这个私钥创建未经过签发者签名的证书
```
pki --req --type priv --in private/svr.pem \
--dn "C=CH, O=yy, CN=x.x.x.x" \
--san x.x.x.x --outform pem > svrReq.pem
```
其中san指subjectAltName，可以多次使用，可以是主机域名，主机名，电子邮件，ipv4地址，ipv6地址。Windows和ios，mac客户端会识别验证这个字段的。

3. 使用CA对服务器证书签名后才是完整的证书了。
```
pki --issue --cacert caCert.pem \
--cakey caKey.pem \
--type pkcs10 --in svrReq.pem --serial 02 --lifetime 182 \
--outform pem > x509/svrCert.pem
```

> [!IMPORTANT]
> 有些vpn客户端要求vpn服务器证书要包含TLS服务器授权Extended Key Usage (EKU) flag
> ```
> --flag serverAuth
> ```

4. 查看证书内容
```
pki --print --in x509/svrCert.pem
```

### strongswan配置
1. 服务器证书`svrCert.pem`放到`/etc/swanctl/x509/`目录
2. 服务器证书的私钥`svrKey.pem`放到`/etc/swanctl/private/`目录
3. 编辑`/etc/swanctl/swanctl.conf`或者在`/etc/swanctl/conf.d/`目录新建以`.conf`结尾的配置文件内容如下
```
connections {
  eap {
    pools = rw_pool
    send_cert = always
    local {
      auth = pubkey
      certs = svrCert.pem
      id = 119.28.30.30
    }
    remote {
      auth = eap-mschapv2
      eap_id = user1
    }
    children {
      eaps {
        local_ts = 0.0.0.0/0
        remote_ts = dynamic
        updown = /usr/lib/ipsec/_updown
      }
      send_certreq = no
    }
  }
}

secrets {
  eap-tom {
    id = user1
    secret = "dFhfthDRE4"
  }
}

pools {
  rw_pool {
    addrs = 10.10.6.4/29
    dns =8.8.8.8,8.8.4.4
  }
}
```

4. 载入配置
```
swanctl --load-all
```

> [!TIP]
> 客户端连接前执行这个命令可即时查看日志
> ```
> swanctl --log
> ```

### iOS、iPad以EAP认证方式连接
- 将自签名的CA证书`caCert.pem`传到客户端iOS/iPad，使用**文件**打开证书文件会有提示，根据提示打开**设置**安装证书后，还必须在**设置**➡️**通用**➡️**关于本机**，最下面的**证书信任设置**里面*开启*对应证书的**针对根证书启用完全信任**。

- 在**通用**➡️**VPN与设备管理**➡️**添加VPN配置...** 界面
1. **类型**选择*IKEv2*
2. **描述**可填写任意名称
3. **服务器**填写VPN服务器的公网ip
4. **远程ID**也填写VPN服务器的公网ip
5. **本地ID**可以留空
6. **用户鉴定**选择*用户名*
7. **用户名**，**密码**就是服务器端添加的EAP用户名和密码。
