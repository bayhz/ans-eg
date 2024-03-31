# 使用strongswan建立ipsec ikev2连接
本文中的配置都是在ipsecVPN网关也就是将strongswan作为服务端的配置，使用的是`ubuntu20.04`
## OS基本配置
可以通过下面任一命令临时开启ip转发
```
echo 1 > /proc/sys/net/ipv4/ip_forward
```

```
sysctl net.ipv4.ip_forward=1
sysctl net.ipv6.conf.all.forwarding=1
```

> [!WARNING] 固化配置
> 要使ip转发配置重启后不失效，需要修改并保存配置文件，打开`/etc/sysctl.conf`配置文件，取消有`net/ipv4/ip_forward=1`这行内容的注释，或者在文件中新插入一行。

> [!INFO] 放通udp:500,4500端口
> - 如果开启了防火墙，那需要放通udp:500,4500端口
> - 如果使用的云服务器那相应安全组也要放通这两个udp端口。

## 安装strongswan

```
sudo apt update -y
```
```
sudo apt install strongswan strongswan-swanctl strongswan-pki -y
```
    

## PSK认证方式建立连接的配置
### 修改swanctl.conf配置文件
编辑`/etc/swanctl/swanctl.conf`内容如下
```
connections {
foo {
    version = 2
    local_addrs = 0.0.0.0/0
    remote_addrs = 0.0.0.0/0
    rekey_time = 0
    local {
      auth = psk
      id = swan1
    }
    remote {
      auth = psk
      id = %any
    }
    children {
      bar {
        start_action = trap
        local_ts = 0.0.0.0/0
        remote_ts = 10.10.0.0/16
        hostaccess = yes
        updown = /usr/lib/ipsec/_updown iptables
        life_time = 0
      }
    }
    pools = rw_pool
  }
}

secrets {
  ike-tom {
    id = zong
    secret = "hdyhggtGuuTdF375FhhfthDRE4"
  }
  ikesvr {
    id = swan
    secret = "hdyhggtGuuTdF375FhhfthDRE4"
  }
}
pools {
  rw_pool {
    addrs = 10.10.9.0/28
    dns =8.8.8.8,8.8.4.4
  }
}
```
- [ ] `foo`是连接的名称，可以自定义名称
- [ ] `version`就是ike的版本号
- [ ] `local_addrs`和`remote_addrs`指的是建立ipsec两端的网关地址，对服务端网关就是local_addrs，你也可以将它直接设置成固定的公网ip，如果服务器上有多个公网ip设置成全零网段那这些ip你都可以用来建立连接；相对来说remote_addrs就是客户端vpn网关ip，客户端一般都来自于公网ip不固定的网络，那通常就只能设置成全零网段了。
- [ ] `local`和`remote`里面就是两端各自的认证信息。只有`auth = psk`时才需要指定id，本端id可以是任意的一个名称，远端id可以设置成`id = %any`这样`secrets`段中定义的ike前缀的认证，客户端都可以用来作为认证来连接。
- [ ] `children`是IKE建立SA的信息，一个连接是可以建立多个SA。当`local_ts`和`remote_ts`设置为`dynamic`[^1]时表示使用一个32位掩码的地址，当然`local_ts`得要设置成`0.0.0.0/0`，否则你就只能访问VPN服务器那一个地址了。
- [ ] `pools`用来用来定义地址池，并用来在连接里指明分配给客户端的ip地址池的名称。其中*rw_pool*就是自定义的地址池名称，`addrs`设置地址池分配ip的范围，`dns`可以用来设置分配的ip使用的dns服务器。*当把地址池设置成30位掩码时，连接第二个客户端后无法解析域名，但可以访问公网ip，建议设置预留足够的地址*。
- [ ] `updown`[^1]指向`_updown`插件脚本[^2]，当前SA建立或删除时触发调用的。如果使用这个脚本你需要确认下是否有*/usr/lib/ipsec/*这个目录和脚本。
- [ ] `hostaccess`使用`updown`脚本时才会用到。
- [ ] `secret`就是IKE的PSK预共享密钥。

> [!WARNING] Linux建立连接时要求PSK大于20个字符！

每次修改配置后要使用这个命令重新载入配置和认证信息使配置生效
> ```
> swanctl --load-all
> ```

如果要借助VPN网关去访问公网，那就需要在nat表中添加一条iptables规则。相当于是将VPN网关服务器作为NAT网关，添加一条源地址是之前设置的客户端ip的snat规则，用来通过VPN服务器的公网ip访问公网。
```
iptables -t nat -A POSTROUTING -s 10.10.0.0/16 -j MASQUERADE
```

 
> [!NOTE] 上面的iptables命令重启服务器会失效，当然你可以通过多种方式固化到系统配置中，*updown*插件可以在建立和删除SA时动态的自动配置*iptables*规则。
> > **在`_updown`文件中以下位置插入*iptables*规则内容，然后将swanctl.conf配置文件中`updown = /usr/lib/ipsec/_updown iptables`这行修改为`updown = /usr/lib/ipsec/_updown`**。
> > 
> > ...
> > 
> > 235 up-client:)
> > 
> > 236        # connection to my client subnet coming up
> > 
> > 237         # If you are doing a custom version, firewa    ll commands go here.
> > 
> > 238        
> > ```
> > iptables -t nat -A POSTROUTING -s $PLUTO_PEER_CLIENT -m policy --dir out --pol ipsec -j ACCEPT
> > ```
> > 
> > 239         
> >
> >```
> > iptables -t nat -A POSTROUTING -s $PLUTO_PEER_SOURCEIP -j MASQUERADE
> > ```
> > 
> > 
> > 240         ;;
> > 
> > 241 down-client:)
> > 
> > 242         # connection to my client subnet going down
> > 
> > 243         # If you are doing a custom version, firewa    ll commands go here.
> > 
> > 244         
> > ```
> > iptables -t nat -D POSTROUTING -s $PLUTO_PEER_CLIENT -m policy --dir out --pol ipsec -j ACCEPT
> > ```
> > 
> > 245         
> > ```
> > iptables -t nat -D POSTROUTING -s $PLUTO_PEER_SOURCEIP -j MASQUERADE
> > ```
> > 
> > 246         ;;
> > 
> > ...
> > 

### iOS、iPad以PSK认证方式连接
在**通用**➡️**VPN与设备管理**➡️**添加VPN配置...** 界面
1. **类型**选择*IKEv2*
2. **描述**可填写任意名称
3. **服务器**填写VPN服务器的公网ip
4. **远程ID**保持和服务器上设置的一致，这里就是`swan1`
5. **本地ID**就是secrets中定义的ike认证信息`zong`，`swan`都行
6. **用户鉴定**选择*无*
7. **使用证书**，*关闭*
8. **密钥**就是`secrets`中定义的各自id的PSK密钥`secret`内容。

> **多个客户端不在同一个网络但本地出口都是同一个公网ip连接VPN时**
> * 当你的VPN服务器有多个网关ip(公网ip)时，你可以使用同一个id和PSK作为客户端连接到服务器的不同公网ip，并且建立连接后这些客户端的内网地址(指VPN服务器分配的ip，通过在VPN服务器执行`swanctl --list-sas`查看到)也是互通的。
> * 当你VPN服务器只有一个网关ip时，你可以建立多个id和PSK作为客户端来连接同一个服务器ip。

### Linux桌面以PSK认证方式连接

这个是以**Ubuntu20**桌面来建立连接。
先安装*network-manager-strongswan*插件，这样在添加vpn连接里就可以看到有*IPsec/IKEv2(strongswan)*的选项了。
```
apt install network-manager-strongswan -y
```
1. 在**设置**➡️**网络**➡️点**VPN**右侧的**+** ，进入添加VPN窗口
2. 选择**IPsec/IKEv2(strongswan)**。
4. **名称**，随便填写。
5. 在**Server**下的**Address**填写VPN服务器的公网IP，**Certificate**选择无，**Identity**不能留空任意填写。
6. 在**Clients**下的**Authentication**选择*Pre-share key*，**Identity**填写VPN服务器预先给客户端定义的ID，点击**Password**右侧的图标选择仅为该用户存储密码，然后填入ID对应的PSK。
7. **Options**栏中选中*Request an inner IP address*。
8. 点击右上角**添加**按钮添加后，就可以连接了。

[^1]: https://docs.strongswan.org/docs/5.9/swanctl/swanctlConf.html#_secrets_pkcs12suffix
[^2]: https://docs.strongswan.org/docs/5.9/plugins/updown.html