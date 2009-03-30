Name:		m2_node
Version:	0.23.3
Release:	1
Source:		m2_node-0.23.3.tar.gz
License:	BSD
Vendor:		Codeforge (Pty) Ltd.
Group:		Applications/System
BuildRoot:	%{_tmppath}/%{name}-%{version}-%{release}-buildroot
Requires:	cfkit
Summary:	m2 messagebus node

%description
Provides service tag based routing for m2 messages

%prep
%setup -q

%build
make

%install
rm -rf $RPM_BUILD_ROOT
make DESTDIR=$RPM_BUILD_ROOT install-rpm

%clean
rm -rf $RPM_BUILD_ROOT

%post
chkconfig m2_node on

%preun
/etc/init.d/m2_node stop
chkconfig m2_node off

%files
/usr/bin/m2_node
/etc/init.d/m2_node
%config /etc/sysconfig/m2_node

%changelog
* Mon Mar 30 2009 Cyan Ogilvie <cyan.ogilvie@gmail.com> 0.23.3-1
- Enabled keepalive and nodelay support

* Mon Mar 30 2009 Cyan Ogilvie <cyan.ogilvie@gmail.com> 0.23.2-1
- Made config system pluggable

* Thu Mar 26 2009 Cyan Ogilvie <cyan.ogilvie@gmail.com> 0.23.1-1
- Changed to cfkit

* Wed Jan 21 2009 Cyan Ogilvie <cyan.ogilvie@gmail.com> 0.20.3-1
- Rename of connection method tcp_coroutine to tcp

* Wed Jan 21 2009 Cyan Ogilvie <cyan.ogilvie@gmail.com> 0.20.2-1
- Fixed sysconfig file permissions

* Tue Jan 20 2009 Cyan Ogilvie <cyan.ogilvie@gmail.com> 0.20.1-1
- Initial RPM release
