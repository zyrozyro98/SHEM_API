String orderConfirmationTitleForStatus(String status) {
  return switch (status) {
    'new' => 'تم استلام طلبك',
    'pending_payment' => 'تم إنشاء طلبك',
    'awaiting_confirmation' => 'تم استلام طلبك وإيصال الدفع',
    'confirmed' => 'تمت الموافقة على طلبك',
    'preparing' => 'طلبك قيد التجهيز',
    'shipped' => 'طلبك جاهز للاستلام من المتجر',
    'picked_up' => 'تم تسليم طلبك للسائق',
    'delivered' => 'تم توصيل طلبك',
    'cancelled' => 'تم إلغاء الطلب',
    _ => 'تم استلام طلبك',
  };
}

String orderConfirmationStatusLabel(String status) {
  return switch (status) {
    'new' => 'طلب جديد',
    'pending_payment' => 'بانتظار الدفع',
    'awaiting_confirmation' => 'بانتظار مراجعة الإيصال',
    'confirmed' => 'تمت الموافقة',
    'preparing' => 'قيد التجهيز',
    'shipped' => 'جاهز للاستلام من المتجر',
    'picked_up' => 'تم تسليم الطلب للسائق',
    'delivered' => 'تم التوصيل',
    'cancelled' => 'ملغي',
    _ => 'قيد المعالجة',
  };
}

String orderConfirmationMessageForStatus(String status) {
  return switch (status) {
    'new' => 'طلبك جديد وبانتظار تأكيد التاجر.',
    'awaiting_confirmation' =>
      'إيصال الدفع قيد المراجعة. سنحدّث حالة الطلب بعد موافقة المسؤول.',
    'pending_payment' => 'طلبك بانتظار استكمال الدفع أو تأكيده.',
    'confirmed' => 'تمت الموافقة على الطلب، وسيبدأ التجهيز قريبًا.',
    'preparing' => 'يجري تجهيز طلبك الآن.',
    'shipped' => 'طلبك جاهز للاستلام من المتجر.',
    'picked_up' => 'تم تأكيد استلام السائق لطلبك، وهو في الطريق إليك.',
    'delivered' => 'نأمل أن تستمتع بطلبك.',
    'cancelled' => 'يمكنك مراجعة تفاصيل الطلب لمعرفة سبب الإلغاء.',
    _ => 'يمكنك متابعة آخر تحديثات طلبك من صفحة الطلبات.',
  };
}
