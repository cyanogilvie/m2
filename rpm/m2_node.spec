Name:		m2_node
Version:	0.20
Release:	1
Source:		m2_node-0.20.tar.gz
License:	BSD
Vendor:		Codeforge (Pty) Ltd.
Group:		Applications/System
BuildRoot:	%{_tmppath}/%{name}-%{version}-%{release}-buildroot
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

%files
/usr/bin/m2_node
/etc/init.d/m2_node
%config /etc/sysconfig/m2_node
